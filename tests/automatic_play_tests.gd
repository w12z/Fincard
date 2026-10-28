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
	investment.data["progress"] = 3
	var budget := sim.state.budget
	var piles := sim.state.deck.size() + sim.state.hand.size() + sim.state.discard.size()
	var preview := sim.forecast_next_turn()
	_expect(preview.cards_played_this_turn == 1 and continuity.data.has("queued_card"), "Forecast includes automatic play without consuming the real queue")
	var events := sim.apply_command(Command.end_turn())
	_expect(_automatic_count(events) == 1 and sim.state.cards_played_this_turn == 1, "Automatic card must emit one CARD_PLAYED and count as the first play")
	_expect(sim.state.investments_played_this_turn == 1 and investment.data["progress"] == 0, "Automatic investment advances cross-turn research counter")
	_expect(sim.state.hand.size() == 6, "Automatic investment's fourth-card trigger draws one extra card")
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


func _test_effect_repeat_is_not_play() -> void:
	var sim := _prepare()
	_grant(&"replay")
	var events := _manual(&"starter_small_business")
	_expect(sim.state.cards_played_this_turn == 1 and sim.state.investments_played_this_turn == 1, "An effect repeat still counts as only one played card")
	_expect(_automatic_count(events) == 0 and sim.state.played_cards_this_turn.size() == 2, "Effect repetition does not generate another automatic play")


func _test_automatic_animation() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
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
	ui._dispatch(Command.end_turn())
	while ui._settlement_active:
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
	_test_effect_repeat_is_not_play()
	await _test_automatic_animation()
	controller.free()
	await process_frame
	print("AUTOMATIC PLAY TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
