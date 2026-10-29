extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _grant(id: StringName) -> Modifier:
	var sim := controller.simulation
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
		"scope": "special", "target": id, "duration": -1,
	}}), sim.state, sim.rng)
	var modifier := StatusRules.find_modifier(sim.state, id)
	modifier.ready_turn = sim.state.turn
	return modifier


func _prepare() -> Simulation:
	controller.start_run(&"example_country")
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.budget = 100
	sim.state.political_capital = 20
	return sim


func _manual(id: StringName) -> Array[Event]:
	var sim := controller.simulation
	sim.state.hand.append(id)
	return sim.apply_command(Command.play_card(id))


func _automatic_count(events: Array[Event]) -> int:
	var count := 0
	for event in events:
		if event.kind == Event.Kind.CARD_PLAYED and event.params.get("automatic", false):
			count += 1
	return count


func _test_automatic_triggers() -> void:
	var sim := _prepare()
	var continuity := _grant(&"project_continuity")
	var investment := _grant(&"investment_research")
	_grant(&"policy_synergy")
	_grant(&"emergency_authority")
	_grant(&"rotation_execution")
	var cabinet := Modifier.new(&"automatic_play_probe", Modifier.Op.ADD, 0, -1, &"probe", Modifier.SCOPE_SPECIAL)
	cabinet.rule = &"event_effects"
	cabinet.data = {"on_kind": Event.Kind.CARD_PLAYED, "effects": [
		{"kind": "gain_budget", "params": {"amount": 1}},
	]}
	sim.state.modifiers.append(cabinet)
	_manual(&"starter_small_business")
	investment.data["progress"] = 2
	var budget := sim.state.budget
	var piles := sim.state.deck.size() + sim.state.hand.size() + sim.state.discard.size()
	var preview := sim.forecast_next_turn()
	_expect(preview.cards_played_this_turn == 1 and continuity.data.has("queued_card"), "Forecast includes automatic play without consuming the real queue")
	var events := sim.apply_command(Command.end_turn())
	_expect(_automatic_count(events) == 1 and sim.state.cards_played_this_turn == 1, "Automatic card must emit one CARD_PLAYED and count as the first play")
	_expect(sim.state.investments_played_this_turn == 1 and investment.data["progress"] == 0, "Automatic investment advances cross-turn research counter")
	_expect(sim.state.hand.size() == 6, "Automatic investment's third-card trigger draws one extra card")
	_expect(sim.state.budget == budget + 1, "Automatic play is free and triggers CARD_PLAYED cabinet effects exactly once")
	_expect(sim.state.deck.size() + sim.state.hand.size() + sim.state.discard.size() == piles, "Automatic play never duplicates or removes the original card")
	_expect(not continuity.data.has("queued_card"), "Automatic play cannot record itself for the next turn")
	_expect(sim.card_costs(&"policy_asset_disposal")["political"] == 0, "Automatic play counts toward the second-card cost waiver")
	var hand_before := sim.state.hand.size()
	_manual(&"policy_asset_disposal")
	_expect(sim.state.flags["policies_played_this_turn"] == 1 and sim.state.political_capital == 4, "Automatic investment and manual policy trigger type synergy")
	_expect(continuity.data["queued_card"] == &"policy_asset_disposal", "First manual play is still recorded after an automatic play")
	_manual(&"starter_small_business")
	_expect(sim.state.cards_played_this_turn == 3 and sim.state.hand.size() == hand_before + 2, "Automatic plus two manual cards trigger third-card draw")
	_expect(continuity.data["queued_card"] == &"policy_asset_disposal", "Later manual plays do not replace the recorded card")
	events = sim.apply_command(Command.end_turn())
	_expect(_automatic_count(events) == 1 and sim.state.flags["policies_played_this_turn"] == 1, "Automatic policy counts toward policy triggers")
	events = sim.apply_command(Command.end_turn())
	_expect(_automatic_count(events) == 0, "No new hand play means no infinite automatic chain")


func _test_repeat_counts_as_play() -> void:
	var sim := _prepare()
	_grant(&"replay")
	var events := _manual(&"starter_small_business")
	_expect(sim.state.cards_played_this_turn == 2 and sim.state.investments_played_this_turn == 2, "Both plays count toward total and investment counters")
	_expect(_automatic_count(events) == 1 and sim.state.played_cards_this_turn.size() == 2, "The second play generates one free automatic play")


func _test_repeat_triggers() -> void:
	for repeat_id in [&"replay", &"repeat_investment"]:
		var sim := _prepare()
		_manual(&"arcadia_policy_bond_yield")
		_grant(repeat_id)
		var research := _grant(&"investment_research")
		research.data["progress"] = 1
		_grant(&"policy_synergy")
		_grant(&"construction_repayment")
		_grant(&"recovery_coordination")
		_grant(&"rotation_execution")
		var continuity := _grant(&"project_continuity")
		var trigger := Modifier.new(&"repeat_probe", Modifier.Op.ADD, 0, -1, &"probe", Modifier.SCOPE_SPECIAL)
		trigger.rule = &"event_effects"
		trigger.data = {"on_kind": Event.Kind.CARD_PLAYED, "effects": [
			{"kind": "gain_budget", "params": {"amount": 1}},
		]}
		sim.state.modifiers.append(trigger)
		sim.state.hand.clear()
		sim.state.deck.clear()
		for i in 10:
			sim.state.deck.append(&"starter_training")
		var budget := sim.state.budget
		var political := sim.state.political_capital
		var discard := sim.state.discard.count(&"starter_small_business")
		var events := _manual(&"starter_small_business")
		_expect(sim.state.cards_played_this_turn == 3 and sim.state.investments_played_this_turn == 2, "Second play advances total and investment counters: %s" % repeat_id)
		_expect(research.data["progress"] == 0 and sim.state.hand.size() == 3, "Second play triggers third-investment research and third-card draw: %s" % repeat_id)
		_expect(sim.state.budget == budget - 2 + 2 + 2 + 2, "Pay once; trigger second-investment refund, third-card refund and two CARD_PLAYED effects: %s" % repeat_id)
		_expect(sim.state.political_capital == political, "Pay one political point and gain one type-synergy refund: %s" % repeat_id)
		_expect(sim.state.discard.count(&"starter_small_business") == discard + 1, "Second play adds no extra discard copy: %s" % repeat_id)
		_expect(_automatic_count(events) == 1 and not continuity.data.has("queued_card"), "Second play is automatic and never records itself: %s" % repeat_id)
		_expect(StatusRules.find_modifier(sim.state, repeat_id) == null, "Repeat is consumed without recursion: %s" % repeat_id)
	var sim := _prepare()
	_grant(&"replay")
	_manual(&"policy_procedural_motion")
	_expect(sim.state.flags["policies_played_this_turn"] == 2 and sim.state.flags["political_policies_played_this_turn"] == 2, "Both policy plays advance policy and political-policy counters")


func _test_aid_and_hand_only_repeat() -> void:
	var sim := _prepare()
	_grant(&"aid_card_repeat")
	sim._gain_aid(&"arcadia_aid_fireside")
	sim.apply_command(Command.use_aid(&"arcadia_aid_fireside"))
	var confidence := sim.economy.value(sim.state, &"confidence")
	var budget := sim.state.budget
	var political := sim.state.political_capital
	var events := _manual(&"arcadia_relief_dole")
	_expect(sim.state.cards_played_this_turn == 2 and sim.state.investments_played_this_turn == 2 and _automatic_count(events) == 1, "Deposit insurance grants two counted plays")
	_expect(sim.economy.value(sim.state, &"confidence") == confidence + 10 and sim.state.budget == budget - 2 and sim.state.political_capital == political - 1, "Deposit insurance plays twice while charging once")
	sim._gain_aid(&"arcadia_aid_fireside")
	sim.apply_command(Command.use_aid(&"arcadia_aid_fireside"))
	_expect(StatusRules.find_modifier(sim.state, &"replay") == null, "Second aid in one turn does not grant another repeat")
	for repeat_id in [&"replay", &"repeat_investment"]:
		sim = _prepare()
		_grant(repeat_id)
		sim._resolve_played_card(&"starter_small_business", true)
		_expect(StatusRules.find_modifier(sim.state, repeat_id) != null and sim.state.cards_played_this_turn == 1, "An automatic play cannot consume a hand-only repeat: %s" % repeat_id)
		events = _manual(&"starter_small_business")
		_expect(_automatic_count(events) == 1 and sim.state.cards_played_this_turn == 3, "The next hand play still plays twice: %s" % repeat_id)


func _test_reform_adjustments() -> void:
	var sim := _prepare()
	_expect(controller.cards[&"starter_efficiency"].rarity == &"common" and controller.cards[&"starter_efficiency"].once_per_run, "Administrative efficiency is common but remains a one-time reform")
	var confidence := sim.economy.value(sim.state, &"confidence")
	_manual(&"arcadia_reform_social_security")
	_expect(sim.economy.value(sim.state, &"confidence") == confidence + 12, "Social security immediately grants twelve confidence")
	sim = _prepare()
	var research := _grant(&"investment_research")
	_manual(&"starter_small_business")
	_manual(&"starter_small_business")
	_expect(research.data["progress"] == 2, "Research waits for the third investment")
	var forecast := sim.forecast_next_turn()
	_expect(research.data["progress"] == 2 and StatusRules.find_modifier(forecast, &"investment_research").data["progress"] == 2, "Research progress carries across turns without forecast mutation")
	var hand := sim.state.hand.size()
	_manual(&"starter_small_business")
	_expect(research.data["progress"] == 0 and sim.state.hand.size() == hand + 1, "Third investment draws exactly one card")


func _test_automatic_animation() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	while ui._pile_motion_active:
		await process_frame
	var sim := controller.simulation
	_grant(&"project_continuity")
	sim.state.budget = 100
	sim.state.political_capital = 20
	sim.state.hand.append(&"starter_small_business")
	ui._dispatch(Command.play_card(&"starter_small_business"))
	for frame in 6:
		await process_frame
	ui._dispatch(Command.end_turn())
	while ui._settlement_active:
		await process_frame
	_expect(ui._flight_active and is_instance_valid(ui._flight_card), "Automatic play starts a visible flight")
	_expect(ui._flight_card.global_position.is_equal_approx(ui._hand_scroll.global_position), "Automatic card flies from the far-left deck/hand area")
	_expect(ui._flight_card.preview_card.id == &"starter_small_business", "Automatic flight shows the recorded card")
	_expect(ui._flight_target != null and not ui._flight_target.visible, "The destination is hidden until the automatic card lands")
	_expect(ui._end_turn_button.disabled, "Turn advancement waits until the flight lands")
	await create_timer(0.4).timeout
	for frame in 6:
		await process_frame
	_expect(not ui._flight_active and ui._flight_layer.get_child_count() == 0, "Automatic flight releases its temporary card")
	_expect(ui._played_table._cards.size() == 1 and ui._played_table._cards[0].visible, "Only the newly automatically played card remains on the table")
	_expect(ui._played_table._cards[0].tooltip_text.begins_with("自动打出（免费）"), "Automatic table cards clearly identify their origin")
	while ui._pile_motion_active:
		await process_frame
	ui._dispatch(Command.end_turn())
	while ui._settlement_active or ui._pile_motion_active:
		await process_frame
	for frame in 6:
		await process_frame
	_expect(ui._played_table._cards.is_empty(), "A subsequent turn with no queued card has a clean table")
	ui.free()
	await process_frame


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_automatic_triggers()
	_test_repeat_counts_as_play()
	_test_repeat_triggers()
	_test_aid_and_hand_only_repeat()
	_test_reform_adjustments()
	await _test_automatic_animation()
	controller.free()
	await process_frame
	print("AUTOMATIC PLAY TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
