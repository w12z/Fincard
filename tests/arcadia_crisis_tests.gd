extends SceneTree

var failures := 0
var controller: GameController
const POST_CRISIS: Array[StringName] = [
	&"arcadia_relief_dole", &"arcadia_relief_works", &"arcadia_relief_ccc", &"arcadia_relief_farm",
	&"arcadia_recover_bank_holiday", &"arcadia_recover_fdic", &"arcadia_recover_gold", &"arcadia_reform_social_security",
]


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare(turn: int = 1) -> Simulation:
	var sim := controller.simulation
	sim.start_run(&"arcadia")
	sim.apply_command(Command.choose_reward([]))
	sim.state.turn = turn
	sim.state.turn_in_year = (turn - 1) % 8 + 1
	sim.state.year = ceili(turn / 8.0)
	sim.state.indicators[&"gdp"] = 200
	sim.state.indicators[&"confidence"] = 90
	sim.state.indicators[&"unemployment"] = 6
	sim.state.indicators[&"inflation"] = 2
	return sim


func _test_frenzy_and_collapse() -> void:
	var sim := _prepare()
	for pair in [[0.19, 0], [0.2, 2], [0.4, 4], [0.6, 6], [2.0, 6], [-1.0, 0]]:
		_expect(is_equal_approx(EconomyBuilder.special_confidence_delta(sim.state, pair[0]), pair[1]), "Frenzy uses complete 0.2-percent steps and a six-point cap")
	sim.state.turn = 17
	_expect(EconomyBuilder.special_confidence_delta(sim.state, 2) == 0, "Frenzy cannot grant a bonus after turn sixteen")
	sim.resolver.resolve(Effect.from_dict({"kind": "remove_modifier", "params": {"scope": "special", "target": "stock_market_frenzy"}}), sim.state, sim.rng)
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {"scope": "special", "target": "confidence_crash", "duration": -1}}), sim.state, sim.rng)
	for pair in [[-0.25, -0.5], [-1.0, -2], [-2.0, -4], [0.5, 0]]:
		_expect(is_equal_approx(EconomyBuilder.special_confidence_delta(sim.state, pair[0]), pair[1]), "Collapse scales continuously with economic contraction only")
	var confidence := float(sim.state.indicators[&"confidence"])
	sim.resolver.resolve(Effect.from_dict({"kind": "adjust_indicator", "params": {"target": "gdp", "amount": -8, "percent": true}}), sim.state, sim.rng)
	_expect(sim.state.indicators[&"confidence"] == confidence, "A direct GDP loss does not invoke collapse or recursive confidence loss")


func _test_worry() -> void:
	var sim := _prepare(8)
	sim._activate_market_worry()
	_expect(StatusRules.find_modifier(sim.state, &"market_worry") == null, "Worry does not appear before turn nine")
	sim.state.turn = 9
	sim._activate_market_worry()
	var worry := StatusRules.find_modifier(sim.state, &"market_worry")
	_expect(worry != null and worry.stacks == 0 and not worry.is_expired(), "Worry is visible at zero layers starting on turn nine")
	sim.state.indicators[&"confidence"] = 89
	sim._settle_market_worry(0.99)
	_expect(worry.stacks == 0, "Neither threshold means no layer")
	sim.state.turn = 10
	sim._settle_market_worry(1.0)
	sim._settle_market_worry(2.0)
	_expect(worry.stacks == 1, "The growth threshold adds at most one layer per turn")
	sim.state.turn = 11
	sim.state.indicators[&"confidence"] = 90
	sim._settle_market_worry(0.2)
	_expect(worry.stacks == 2, "Confidence alone can add a layer")
	sim.state.turn = 16
	worry.stacks = 7
	sim._settle_market_worry(2.0)
	_expect(worry.stacks == 8, "Both thresholds still add one layer and the maximum is eight")
	sim.state.turn = 17
	sim._settle_market_worry(2.0)
	_expect(worry.stacks == 8, "Worry stops accumulating after turn sixteen")


func _test_turn_end_crash() -> void:
	var sim := _prepare(16)
	sim._activate_market_worry()
	var worry := StatusRules.find_modifier(sim.state, &"market_worry")
	worry.stacks = 7
	sim._schedule_event()
	_expect(sim.state.pending_event == &"", "The crash does not fire at the start of turn sixteen")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.turn == 16 and sim.state.pending_event == &"arcadia_ev_black_thursday" and sim.state.pending_rewards.is_empty(), "Turn sixteen settles before the crash, and annual rewards wait for its resolution")
	_expect(worry.stacks == 8, "Turn sixteen contributes its final worry layer")
	var gdp := float(sim.state.indicators[&"gdp"])
	var confidence := float(sim.state.indicators[&"confidence"])
	var unemployment := float(sim.state.indicators[&"unemployment"])
	var budget := sim.state.budget
	var definition: EconomyEventDef = controller.events[&"arcadia_ev_black_thursday"]
	var effects := sim.event_effects(definition.effects)
	_expect(effects[0].params["amount"] == -32 and effects[1].params["amount"] == -40, "Eight worry layers produce one combined 32-percent GDP loss and forty confidence loss")
	sim.event_choice_available(-1)
	_expect(worry.stacks == 8 and StatusRules.find_modifier(sim.state, &"stock_market_frenzy") != null, "Affordability preview cannot consume live market modifiers")
	sim.apply_command(Command.resolve_event(-1))
	_expect(is_equal_approx(sim.state.indicators[&"gdp"], gdp * 0.68) and is_equal_approx(sim.state.indicators[&"confidence"], confidence - 40), "Actual losses match the displayed crisis values without applying collapse to the event")
	_expect(is_equal_approx(sim.state.indicators[&"unemployment"], unemployment + 4), "The prior economic settlement is not repeated after crisis confirmation")
	_expect(StatusRules.find_modifier(sim.state, &"stock_market_frenzy") == null and StatusRules.find_modifier(sim.state, &"market_worry") == null and StatusRules.find_modifier(sim.state, &"confidence_crash") != null, "The crash consumes worry and replaces frenzy with collapse")
	_expect(sim.state.budget == budget and not sim.state.pending_rewards.is_empty(), "Crisis resolution opens annual rewards without prematurely paying income")
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.turn == 17 and sim.state.year == 3 and sim.state.pending_event == &"arcadia_ev_market_stabilization", "The next year begins with the exclusive stabilization event")
	_expect(sim.state.budget == int(floor(budget * 0.5)) + 40, "Annual income is paid only once after preparation")
	for modifier in sim.state.modifiers:
		if modifier.source == &"股灾余波":
			_expect(modifier.remaining_turns == 6, "Post-settlement crisis effects retain all six future settlements")


func _test_reward_gates() -> void:
	var sim := _prepare()
	for turn in [1, 8, 9, 15, 16]:
		sim.state.turn = turn
		for id in POST_CRISIS:
			_expect(not sim._reward_available(Reward.Type.CARD, id), "Crisis cards are excluded from earlier rewards: %s" % id)
	_expect(sim.state.hand.count(&"arcadia_relief_dole") + sim.state.deck.count(&"arcadia_relief_dole") + sim.state.discard.count(&"arcadia_relief_dole") == 2, "Starter relief cards are preserved")
	sim = _prepare(16)
	sim.turns.enter(TurnStateMachine.Phase.TURN_END, sim.state)
	for id in POST_CRISIS:
		_expect(sim._reward_available(Reward.Type.CARD, id), "Preparation for turn seventeen already unlocks crisis cards: %s" % id)
	sim = _prepare(17)
	sim.state.deck.append(&"arcadia_reform_social_security")
	sim.state.flags["enacted:arcadia_recover_bank_holiday"] = true
	controller.rules["random_event_chance"] = 1.0
	sim._schedule_event()
	_expect(sim.state.pending_event == &"arcadia_ev_market_stabilization" and sim.state.pending_event_choices.size() == 1 and sim.state.pending_event_choices[0]["label"] == "获得卡牌", "The exclusive event overrides random events and has one acquire-card option")
	sim.apply_command(Command.resolve_event(0))
	_expect(sim.state.pending_rewards.size() == 1 and sim.state.pending_rewards[0]["options"].size() == 3, "Clicking the event option creates three distinct card choices")
	var group: Dictionary = sim.state.pending_rewards[0]
	var seen := {}
	for option: Reward in group["options"]:
		_expect(not seen.has(option.id) and POST_CRISIS.has(option.id) and not option.id in [&"arcadia_reform_social_security", &"arcadia_recover_bank_holiday"], "Owned and enacted laws are replaced from the post-crisis pool")
		seen[option.id] = true
	var hand_size := sim.state.hand.size()
	var budget := sim.state.budget
	var pick: Reward = group["options"][0]
	var token := str(group["token"])
	sim.apply_command(Command.claim_reward(0, 0, token))
	_expect(sim.state.hand.size() == hand_size + 1 and sim.state.hand.back() == pick.id and sim.state.turn == 17 and sim.state.budget == budget, "The chosen card is granted to the current hand without advancing time or paying annual income")
	_expect(sim.state.pending_event == &"" and sim.state.pending_rewards.is_empty(), "No random event is added after the exclusive reward")
	_expect(sim.apply_command(Command.claim_reward(0, 0, token)).is_empty(), "A completed event reward cannot be claimed twice")
	for pair in [[19, &"arcadia_ev_financial_reorganization"], [21, &"arcadia_ev_recovery_plan"]]:
		sim = _prepare(pair[0])
		sim._schedule_event()
		_expect(sim.state.pending_event == pair[1], "The later recovery event also takes exclusive precedence")
		sim.apply_command(Command.resolve_event(0))
		sim.apply_command(Command.choose_reward([]))
		_expect(sim.state.turn == pair[0] and sim.state.pending_rewards.is_empty() and sim.state.pending_event == &"", "Skipping event cards returns to the same turn without annual setup")
	controller.rules["random_event_chance"] = 0.0


func _test_victory_and_deadline() -> void:
	var sim := _prepare(23)
	sim.state.indicators[&"gdp"] = 250
	sim.state.indicators[&"unemployment"] = 3
	sim._check_end_conditions()
	_expect(sim.state.run_status == GameState.RunStatus.RUNNING, "Victory is unavailable before turn twenty-four")
	sim.state.turn = 24
	sim._check_end_conditions()
	_expect(sim.state.run_status == GameState.RunStatus.WON, "Victory becomes available at turn twenty-four")
	sim = _prepare(40)
	sim.state.indicators[&"gdp"] = 250
	sim.state.indicators[&"unemployment"] = 3
	sim.apply_command(Command.end_turn())
	_expect(sim.state.run_status == GameState.RunStatus.WON, "The final fortieth settlement can still win")
	sim = _prepare(40)
	sim.state.indicators[&"gdp"] = 100
	sim.apply_command(Command.end_turn())
	_expect(sim.state.run_status == GameState.RunStatus.LOST and sim.state.flags.get("loss_reason") == "deadline", "Unfinished runs lose at turn forty")


func _test_reward_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	root.add_child(ui)
	ui.setup(controller, &"arcadia")
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	sim.state.turn = 17
	sim._schedule_event()
	ui._render()
	var choices: Array[Button] = []
	for child in ui._overlay_box.get_children():
		if child is Button:
			choices.append(child)
	_expect(choices.size() == 1 and choices[0].text == "获得卡牌", "The initial popup presents exactly one acquire-card button")
	if choices.size() == 1:
		choices[0].pressed.emit()
		var row: HBoxContainer = ui._overlay_box.get_child(1)
		_expect(row.get_child_count() == 3, "The acquire button opens three full card faces immediately")
		var card: CardButton = row.get_child(0)
		_expect(card.tooltip_text.is_empty() and not card.preview_enabled, "Event card choices do not restore duplicate hover previews")
		var hand_size := sim.state.hand.size()
		card.pressed.emit()
		_expect(sim.state.hand.size() == hand_size + 1 and not ui._overlay_root.visible, "Clicking a card closes selection and places it in the hand")
	ui.free()
	await process_frame


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_frenzy_and_collapse()
	_test_worry()
	_test_turn_end_crash()
	_test_reward_gates()
	_test_victory_and_deadline()
	await _test_reward_ui()
	controller.free()
	print("ARCADIA CRISIS TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
