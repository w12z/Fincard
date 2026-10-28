extends SceneTree

var failures := 0
var controller: GameController
var ui: GameUI
var capture_directory := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_directory = arg.trim_prefix("--capture=")
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _frames(count: int = 6) -> void:
	for frame in count:
		await process_frame


func _prepare(scenario: StringName = &"example_country", turn: int = 1) -> void:
	ui.setup(controller, scenario)
	ui._dispatch(Command.choose_reward([]))
	while ui._pile_motion_active:
		await process_frame
	var sim := controller.simulation
	sim.state.turn = turn
	sim.state.turn_in_year = (turn - 1) % 8 + 1
	sim.state.year = (turn - 1) / 8 + 1
	sim.state.budget = 100
	sim.state.political_capital = 10
	sim.state.hand.assign([&"starter_small_business", &"starter_training", &"starter_infrastructure"])
	ui._dispatch(Command.play_card(&"starter_small_business"))
	await _frames()
	await create_timer(0.85).timeout


func _wait_settlement() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (ui._settlement_active or ui._pile_motion_active) and Time.get_ticks_msec() < deadline:
		_expect(not ui._overlay_root.visible and not ui._meeting_page.visible, "No event/reward/meeting may appear before settlement finishes")
		await process_frame
	_expect(not ui._settlement_active, "Settlement animation must finish")
	await _frames()


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory.path_join(filename))


func _test_normal_turn() -> void:
	await _prepare()
	var before_text: String = ui._indicator_rows[0]["label"].text
	var sim := controller.simulation
	ui._dispatch(Command.end_turn())
	_expect(ui._settlement_active and ui._turn_settlement.visible, "Ending turn starts a visible input-blocking settlement")
	_expect(ui._indicator_rows[0]["label"].text == before_text, "Current economic numbers do not jump immediately")
	_expect(ui._played_table._cards.size() == 1 and ui._hand_box.get_child_count() == 2, "Old cards stay visible during numeric settlement")
	var turn := sim.state.turn
	ui._dispatch(Command.end_turn())
	_expect(sim.state.turn == turn, "Repeated end-turn commands cannot settle twice")
	await create_timer(0.22).timeout
	await _capture("fincard-turn-settlement.png")
	await _wait_settlement()
	_expect(ui._played_table._cards.is_empty(), "Old played cards clear after numeric settlement")
	_expect(ui._hand_box.get_child_count() == sim.state.hand.size(), "Only the new hand appears after clearing")
	_expect(ui._indicator_rows[0]["label"].text.ends_with(TextFormatter.fmt(sim.economy.value(sim.state, &"gdp"))), "Animated numbers agree with actual final state")


func _test_reward_then_meeting() -> void:
	await _prepare(&"example_country", 8)
	var sim := controller.simulation
	ui._dispatch(Command.end_turn())
	_expect(ui._settlement_active and not ui._overlay_root.visible, "Fourth-turn reward remains hidden while settling")
	await _wait_settlement()
	_expect(ui._played_table._cards.is_empty() and ui._hand_box.get_child_count() == 0, "Table and hand are both cleared before the reward")
	_expect(ui._overlay_root.visible and not ui._meeting_page.visible, "Periodic reward appears only after settlement and clearing")
	ui._dispatch(Command.choose_reward([]))
	_expect(ui._meeting_page.visible, "Annual meeting follows the completed periodic reward")
	ui._dispatch(Command.choose_reward([]))
	while ui._pile_motion_active:
		await process_frame
	await _frames()
	_expect(sim.state.turn == 9 and sim.state.year == 2, "Annual preparation continues normally without double settlement")


func _test_fixed_event() -> void:
	await _prepare(&"arcadia", 16)
	ui._dispatch(Command.end_turn())
	_expect(ui._settlement_active and not ui._overlay_root.visible, "Scheduled crisis cannot skip the settlement animation")
	await _wait_settlement()
	_expect(controller.simulation.state.pending_event == &"arcadia_ev_black_thursday", "Original scheduled crisis is retained")
	_expect(ui._overlay_root.visible and ui._played_table._cards.is_empty() and ui._hand_box.get_child_count() == 0, "Crisis appears after both old card areas clear")


func _test_modifier_grid() -> void:
	await _prepare()
	var sim := controller.simulation
	for index in 31:
		var modifier := Modifier.new(StringName("grid_probe_%d" % index), Modifier.Op.ADD, 0.1, -1, &"grid", &"coefficient")
		sim.state.modifiers.append(modifier)
	ui._render()
	await _frames(12)
	var grid := ui._effect_icons
	var scroll := grid.get_parent() as ScrollContainer
	_expect(ceili(float(grid.get_child_count()) / grid.columns) <= 3, "Modifier grid never exceeds three rows")
	for badge in grid.get_children():
		_expect(badge.size.x <= 26 and badge.size.y <= 26, "Modifier badges are compact 24px icons")
	_expect(scroll.get_h_scroll_bar().visible, "Only excess beyond three rows requires horizontal scrolling")
	await _capture("fincard-modifier-grid.png")
	await _prepare()
	await _frames(12)
	_expect(not (ui._effect_icons.get_parent() as ScrollContainer).get_h_scroll_bar().visible, "Small modifier sets do not show a scrollbar")


func _test_same_source_expiration() -> void:
	await _prepare()
	var sim := controller.simulation
	sim.state.modifiers.clear()
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.4, 1, &"same-source", &"coefficient"))
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.4, 3, &"same-source", &"coefficient"))
	var before := sim.state.snapshot()
	var events := sim.apply_command(Command.end_turn())
	var settled := TurnSettlement.settled_state(before, events, sim)
	_expect(settled.modifiers.size() == 1, "Expiring one investment must not erase another live same-name modifier in the animation")
	_expect(is_equal_approx(sim.economy.value(settled, &"growth"), sim.economy.value(sim.state, &"growth")), "Animated derived growth correctly accounts for one expired source")


func _test_sequential_numbers_and_sound() -> void:
	await _prepare()
	var audio := SfxAudio.ensure(ui)
	var saved_muted := audio.muted
	var saved_volume := audio.volume
	audio.set_muted(false, false)
	audio.set_volume(0.8, false)
	await create_timer(0.3).timeout
	var landed: Array[StringName] = []
	var sounds: Array[StringName] = []
	var on_landed := func(id: StringName) -> void: landed.append(id)
	var on_sound := func(id: StringName) -> void:
		if id == &"effect_arrive":
			sounds.append(id)
	ui._turn_settlement.indicator_settled.connect(on_landed)
	audio.sound_played.connect(on_sound)
	var first: Label = ui._indicator_rows[0]["label"]
	var second: Label = ui._indicator_rows[1]["label"]
	var original_second := second.text
	var changes: Array[Dictionary] = [
		{"id": &"gdp", "name": "GDP", "label": first, "from": 100.0, "to": 102.0, "color": UiTheme.POSITIVE},
		{"id": &"inflation", "name": "通胀", "label": second, "from": 3.0, "to": 2.5, "color": UiTheme.POSITIVE},
	]
	ui._turn_settlement.play(changes, ui._forecast.get_global_rect())
	await create_timer(0.40).timeout
	_expect(landed == [&"gdp"] and sounds.size() == 1, "First number finishes and sounds once before the second starts")
	_expect(second.text == original_second, "Later indicators do not change while the first one settles")
	_expect(ui._turn_settlement.get_child_count() <= 1, "Only one settlement number is flying at a time")
	await create_timer(0.7).timeout
	_expect(landed == [&"gdp", &"inflation"] and sounds.size() == 2, "Each changed indicator settles in order with its own sound")
	_expect(first.text == "GDP：102" and second.text == "通胀：2.5", "Sequential animation lands on exact final values")
	ui._turn_settlement.clear()
	ui._turn_settlement.indicator_settled.disconnect(on_landed)
	audio.sound_played.disconnect(on_sound)
	audio.set_volume(saved_volume, false)
	audio.set_muted(saved_muted, false)


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	ui = GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _test_normal_turn()
	await _test_reward_then_meeting()
	await _test_fixed_event()
	await _test_modifier_grid()
	await _test_same_source_expiration()
	await _test_sequential_numbers_and_sound()
	ui.free()
	controller.free()
	await process_frame
	print("TURN SETTLEMENT UI TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
