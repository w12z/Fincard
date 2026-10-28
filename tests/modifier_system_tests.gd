extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare(scenario: StringName = &"example_country") -> Simulation:
	var sim := controller.simulation
	sim.start_run(scenario)
	sim.apply_command(Command.choose_reward([]))
	sim.state.budget = 50
	sim.state.political_capital = 20
	return sim


func _grant(sim: Simulation, id: StringName, active: bool = false) -> Modifier:
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
		"scope": "special", "target": id, "duration": -1, "stacks": 1,
	}}), sim.state, sim.rng)
	var modifier := StatusRules.find_modifier(sim.state, id)
	if active:
		modifier.ready_turn = sim.state.turn
	return modifier


func _play(sim: Simulation, id: StringName) -> Array[Event]:
	sim.state.hand.assign([id])
	var events := sim.apply_command(Command.play_card(id))
	_expect(not events.is_empty(), "Card must play: %s" % id)
	return events


func _test_snapshot_and_layers() -> void:
	var sim := _prepare()
	var power := _grant(sim, &"project_continuity")
	_expect(power.stacks == 1 and power.remaining_turns == -1 and power.scope == Modifier.SCOPE_SPECIAL, "A permanent power is one layer in the unified modifier list")
	power.data["queued_card"] = &"starter_training"
	power.data["queued_turn"] = sim.state.turn + 1
	var copy := sim.state.snapshot()
	var copied := StatusRules.find_modifier(copy, &"project_continuity")
	copied.data["queued_card"] = &"example_card"
	copied.stacks = 3
	_expect(power.data["queued_card"] == &"starter_training" and power.stacks == 1, "Modifier snapshots isolate layer counts and trigger data")
	var numeric := Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.1, -1, &"layers", &"coefficient")
	numeric.stacks = 3
	sim.state.modifiers.append(numeric)
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), 0.5), "Numeric modifier layers participate in economic evaluation")
	for property in sim.state.get_property_list():
		_expect(property["name"] != "statuses", "GameState must not retain a second live ability list")


func _test_second_card_free() -> void:
	var sim := _prepare()
	_play(sim, &"reform_emergency_authority")
	_expect(sim.card_costs(&"starter_infrastructure")["budget"] == 4, "A newly acquired delayed modifier cannot waive costs before activation")
	sim.apply_command(Command.end_turn())
	_play(sim, &"starter_small_business")
	var budget := sim.state.budget
	var political := sim.state.political_capital
	_expect(sim.card_costs(&"starter_infrastructure")["budget"] == 0 and sim.card_costs(&"starter_infrastructure")["political"] == 0, "The second manual card waives both resources")
	_play(sim, &"starter_infrastructure")
	_expect(sim.state.budget == budget and sim.state.political_capital == political, "The second card is actually free")
	_expect(sim.card_costs(&"starter_infrastructure")["budget"] == 4, "A third card no longer receives the waiver")


func _test_aid_replay() -> void:
	var sim := _prepare()
	_play(sim, &"arcadia_recover_fdic")
	sim.apply_command(Command.end_turn())
	sim._gain_aid(&"arcadia_aid_fireside")
	sim.apply_command(Command.use_aid(&"arcadia_aid_fireside"))
	var replay := StatusRules.find_modifier(sim.state, &"replay")
	_expect(replay != null and replay.stacks == 1 and replay.remaining_turns == 1, "The first aid grants a real one-layer replay modifier")
	var confidence := float(sim.state.indicators[&"confidence"])
	var budget := sim.state.budget
	_play(sim, &"arcadia_relief_dole")
	_expect(sim.state.indicators[&"confidence"] == confidence + 10 and sim.state.budget == budget - 2, "Replay resolves the effect twice but pays only once")
	_expect(StatusRules.find_modifier(sim.state, &"replay") == null and sim.state.cards_played_this_turn == 1 and sim.state.played_cards_this_turn.size() == 2, "Replay consumes its modifier without recursively counting as another manual play")
	sim.apply_command(Command.use_aid(&"arcadia_aid_fireside"))
	_expect(StatusRules.find_modifier(sim.state, &"replay") == null, "A second aid in the same turn does not grant another replay")


func _test_next_turn_replay() -> void:
	var sim := _prepare()
	var modifier := _grant(sim, &"project_continuity", true)
	_play(sim, &"starter_training")
	var budget := sim.state.budget
	var forecast := sim.forecast_next_turn()
	_expect(modifier.data.get("queued_card") == &"starter_training", "Forecast does not consume the live queued replay")
	var events := sim.apply_command(Command.end_turn())
	var repeats := 0
	for event in events:
		if event.kind == Event.Kind.CARD_PLAYED and event.params.get("automatic", false):
			repeats += 1
	_expect(repeats == 1 and sim.state.cards_played_this_turn == 1, "The next turn starts with one free automatic play that counts as a played card")
	_expect(sim.state.budget == budget and not modifier.data.has("queued_card"), "The queued replay is free and consumed exactly once")
	for id in sim.economy.indicator_ids:
		_expect(is_equal_approx(sim.economy.value(sim.state, id), sim.economy.value(forecast, id)), "Forecast includes queued replay: %s" % id)


func _test_types_and_cross_turn_counter() -> void:
	var sim := _prepare()
	_grant(sim, &"rotation_execution", true)
	_play(sim, &"starter_small_business")
	_play(sim, &"arcadia_policy_bond_yield")
	_play(sim, &"arcadia_reform_austerity")
	_expect(sim.state.political_capital == 18, "Playing all three types refunds two points once")
	_play(sim, &"arcadia_reform_austerity")
	_expect(sim.state.political_capital == 16, "The all-types refund cannot retrigger in the same turn")
	sim = _prepare()
	var counter := _grant(sim, &"investment_research", true)
	for i in 3:
		_play(sim, &"starter_small_business")
	_expect(counter.data.get("progress") == 3, "Investment draw tracks its first three cards")
	sim.apply_command(Command.end_turn())
	_expect(counter.data.get("progress") == 3, "Investment progress survives a turn boundary")
	var events := _play(sim, &"starter_small_business")
	var draws := 0
	for event in events:
		if event.kind == Event.Kind.CARDS_DRAWN:
			draws += int(event.params["count"])
	_expect(draws == 1 and counter.data.get("progress") == 0, "The fourth investment draws one card and resets the counter")


func _test_card_choices_and_political_reserve() -> void:
	var sim := _prepare()
	sim.state.hand.assign([&"reform_policy_reserve", &"starter_training"])
	sim.apply_command(Command.play_card(&"reform_policy_reserve"))
	sim.state.deck.assign([&"starter_small_business", &"starter_infrastructure", &"example_card", &"starter_efficiency"])
	var turn := sim.state.turn
	sim.apply_command(Command.end_turn())
	_expect(sim.state.flags.get("pending_retain", false) and sim.state.turn == turn, "Ending the turn opens retention selection before settlement")
	_expect(sim.apply_command(Command.play_card(&"starter_training")).is_empty(), "Retention selection blocks ordinary actions")
	sim.apply_command(Command.choose_retained_card(0))
	_expect(sim.state.turn == turn + 1 and sim.state.hand.size() == 5 and sim.state.hand[0] == &"starter_training", "The retained card survives alongside four normal draws")
	sim = _prepare()
	_grant(sim, &"midterm_review", true)
	sim.apply_command(Command.end_turn())
	_expect(sim.state.flags.get("pending_review", false), "Start-of-turn review is offered after normal draws")
	var hand_size := sim.state.hand.size()
	sim.apply_command(Command.choose_review_card(0))
	_expect(sim.state.hand.size() == hand_size + 1 and not sim.state.flags.get("pending_review", false), "Review discards one and draws two exactly once")
	_expect(sim.apply_command(Command.choose_review_card(0)).is_empty(), "A completed review cannot be repeated")
	sim = _prepare()
	var reserve := _grant(sim, &"agenda_reserve", true)
	sim.state.turn = 8
	sim.state.turn_in_year = 8
	sim.apply_command(Command.end_turn())
	_expect(int(reserve.data.get("saved", 0)) == 2, "Political reserve stores at most two points across annual preparation")
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.political_capital == 5 and not reserve.data.has("saved"), "Stored points are added after reset exactly once")
	sim.state.political_capital = 0
	sim.apply_command(Command.end_turn())
	_expect(sim.state.political_capital == 3, "An empty political reserve does not create points")


func _test_fiscal_and_economic_boundaries() -> void:
	var sim := _prepare()
	_grant(sim, &"deficit_spending")
	sim.state.budget = -31
	_expect(sim.budget_floor() == -32 and sim.can_spend_budget(1) and not sim.can_spend_budget(2), "Deficit spending is bounded by current annual income")
	sim._fire_event(&"starter_supply")
	_expect(not sim.event_choice_available(0) and sim.event_choice_available(1), "Events respect the same deficit limit and retain a free choice")
	sim = _prepare()
	sim.state.indicators[&"inflation"] = 6
	sim.state.indicators[&"unemployment"] = 12
	sim.state.budget = 0
	var delta := float(sim.economy.equations[&"confidence"].call(sim.state, sim.economy, sim.rng))
	_expect(is_equal_approx(delta, -1.6), "Inflation deviation and excess unemployment each reduce confidence by one fifth")
	sim.state.budget = -20
	delta = float(sim.economy.equations[&"confidence"].call(sim.state, sim.economy, sim.rng))
	_expect(is_equal_approx(delta, -5.6), "A deficit of twenty adds exactly four confidence loss per settlement")
	sim = _prepare(&"arcadia")
	sim.state.indicators[&"gdp"] = 250
	sim.state.indicators[&"unemployment"] = 3
	sim.state.turn = 23
	sim._check_end_conditions()
	_expect(sim.state.run_status == GameState.RunStatus.RUNNING, "Arcadia cannot win before the twenty-fourth turn")
	sim.state.turn = 24
	sim._check_end_conditions()
	_expect(sim.state.run_status == GameState.RunStatus.WON, "Arcadia can win at the twenty-fourth turn")


func _test_reward_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	var sim := controller.simulation
	var count := sim.state.pending_rewards.size()
	var deck_count := sim.state.deck.size()
	var token := str(sim.state.pending_rewards[0]["token"])
	for child in ui._overlay_box.get_children():
		if child is Button and child.text.begins_with("领取卡牌奖励"):
			child.pressed.emit()
			break
	var row: HBoxContainer = ui._overlay_box.get_child(1)
	_expect(row.get_child_count() == 3, "A card reward opens three full card faces")
	var choice: CardButton = row.get_child(0)
	_expect(choice.find_child("Illustration", true, false) != null and choice.find_child("Rarity", true, false) == null, "Reward cards share the illustrated face without a text rarity label")
	_expect(choice.tooltip_text.is_empty() and not choice.preview_enabled, "Card reward selections do not show duplicate hover details")
	choice.pressed.emit()
	_expect(sim.state.pending_rewards.size() == count - 1 and sim.state.deck.size() == deck_count + 1 and sim.state.turn == 0, "Picking a card claims only that group and leaves annual setup pending")
	_expect(sim.apply_command(Command.claim_reward(0, 0, token)).is_empty(), "A stale reward token cannot claim a second group")
	ui._dispatch(Command.choose_reward([]))
	await process_frame
	for badge: Button in ui._effect_icons.get_children():
		_expect(badge.text.is_empty() and badge.custom_minimum_size.x <= 36 and not badge.tooltip_text.is_empty(), "Modifier badges are compact icons with hover-only details")
	ui.setup(controller, &"arcadia")
	for child in ui._overlay_box.get_children():
		if child is Button and child.text == "领取援助奖励":
			child.pressed.emit()
			break
	row = ui._overlay_box.get_child(1)
	_expect(row.get_child_count() == 3, "Aid rewards use the same three-card selection")
	choice = row.get_child(0)
	_expect(choice.preview_aid and choice.find_child("Costs", true, false) == null, "Aid reward faces do not invent card costs")
	_expect(choice.tooltip_text.is_empty() and not choice.preview_enabled, "Aid reward selections do not show duplicate hover details")
	choice.pressed.emit()
	_expect(sim.aid_count() > 0 and sim.aid_count() <= 3, "Aid selection grants independent aid items within capacity")
	ui.free()
	await process_frame


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_snapshot_and_layers()
	_test_second_card_free()
	_test_aid_replay()
	_test_next_turn_replay()
	_test_types_and_cross_turn_counter()
	_test_card_choices_and_political_reserve()
	_test_fiscal_and_economic_boundaries()
	await _test_reward_ui()
	controller.free()
	print("MODIFIER SYSTEM TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
