extends SceneTree

var failures := 0
var controller: GameController
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


func _prepare(scenario: StringName = &"arcadia") -> Simulation:
	var sim := controller.simulation
	sim.rng = Rng.new(7)
	sim.start_run(scenario)
	sim.apply_command(Command.choose_reward([]))
	return sim


func _assert_prediction(sim: Simulation) -> void:
	var original := var_to_str(sim.state.indicators)
	var original_rng := sim.rng.snapshot().next_int(1000000)
	var original_deck := sim.state.deck.duplicate()
	var original_flags := sim.state.flags.duplicate(true)
	var original_aids := sim.state.aids.duplicate(true)
	var durations: Array[int] = []
	for modifier in sim.state.modifiers:
		durations.append(modifier.remaining_turns)
	var next := sim.forecast_next_turn()
	var repeated := sim.forecast_next_turn()
	_expect(next != null and repeated != null, "Playable state must have a forecast")
	_expect(original == var_to_str(sim.state.indicators) and sim.state.deck == original_deck and sim.state.flags == original_flags and sim.state.aids == original_aids, "Forecast must not mutate live indicators, cards, flags or aid uses")
	_expect(sim.rng.snapshot().next_int(1000000) == original_rng, "Forecast must not consume the live RNG")
	for i in durations.size():
		_expect(sim.state.modifiers[i].remaining_turns == durations[i], "Forecast must not consume live modifier duration")
	_expect(next.indicators == repeated.indicators and next.budget == repeated.budget, "Repeated previews must be stable")
	sim.apply_command(Command.end_turn())
	# Match the forecast's no-new-reward assumption at the annual boundary.
	if not sim.state.pending_rewards.is_empty():
		sim.apply_command(Command.choose_reward([]))
	for id in sim.economy.indicator_ids + sim.economy.derived_ids:
		_expect(is_equal_approx(sim.economy.value(next, id), sim.economy.value(sim.state, id)), "Forecast must match actual next-turn effective value: %s" % id)
	_expect(next.budget == sim.state.budget and next.political_capital == sim.state.political_capital, "Forecast includes actual monthly and annual resource transitions")
	_expect(next.run_status == sim.state.run_status, "Forecast respects victory, loss and deadline checks")


func _test_forecast() -> void:
	var sim := _prepare()
	sim._appoint_cabinet(&"arcadia_cab_interior")
	sim._appoint_cabinet(&"arcadia_cab_labor")
	sim.state.modifiers.append(Modifier.new(&"interest_rate", Modifier.Op.ADD, -2, 1))
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.2, 1, &"", &"coefficient"))
	_assert_prediction(sim)
	sim = _prepare()
	sim._appoint_cabinet(&"arcadia_cab_agriculture")
	sim._appoint_cabinet(&"arcadia_cab_fed")
	sim._appoint_cabinet(&"arcadia_cab_treasury")
	sim.state.turn = 8
	sim.state.turn_in_year = 8
	sim.state.budget = -7
	sim.state.modifiers.append(Modifier.new(&"annual_income", Modifier.Op.ADD, 6, 1, &"", &"fiscal"))
	_assert_prediction(sim)
	sim = _prepare()
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.ADD, 100, -1, &"", &"coefficient"))
	sim.state.indicators[&"confidence"] = 99.9
	sim.economy.refresh_derived(sim.state)
	_assert_prediction(sim)
	sim = _prepare()
	sim.state.turn = 23
	sim.state.turn_in_year = 7
	_assert_prediction(sim)
	_expect(sim.state.pending_event == &"arcadia_ev_black_thursday" and sim.forecast_next_turn() == null, "Forecast waits for unresolved events, without guessing choices")
	sim = _prepare()
	sim.state.turn = 48
	sim.state.turn_in_year = 8
	sim.state.year = 6
	_assert_prediction(sim)
	sim = _prepare()
	sim.state.turn = 25
	sim.state.turn_in_year = 1
	sim.state.year = 4
	sim.state.indicators[&"gdp"] = 250
	_assert_prediction(sim)
	sim = _prepare()
	sim.state.indicators[&"confidence"] = 0
	_assert_prediction(sim)


func _test_parameters() -> void:
	var sim := _prepare()
	_expect(ModifierDisplay.entries(sim, controller.labels).size() == 3, "A fresh economy exposes exactly three default parameters")
	sim.economy.scenario_coefficients[&"inflation_target"] = 3.0
	sim.state.modifiers.append(Modifier.new(&"infl_anchor", Modifier.Op.ADD, 0.04, 2, &"", &"coefficient"))
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.MUL, 2, -1, &"", &"coefficient"))
	var entries := ModifierDisplay.entries(sim, controller.labels)
	var seen := {}
	for entry in entries:
		_expect(not seen.has(entry["key"]), "Each parameter gets exactly one merged display")
		seen[entry["key"]] = entry
	var coefficients := sim.economy.base_coefficients.duplicate()
	coefficients.merge(sim.economy.scenario_coefficients, true)
	for target in coefficients:
		var key := "coefficient:%s" % target
		_expect(seen.has(key), "Every economic coefficient must be visible: %s" % target)
		if seen.has(key):
			_expect(seen[key]["value_text"] == TextFormatter.fmt(sim.economy.coefficient(sim.state, target)), "Badge displays effective coefficient, including scenario overrides and modifiers")
	_expect("基础值 3" in seen["coefficient:inflation_target"]["tooltip"], "Scenario overrides of base parameters remain inspectable")
	_expect("有效值 0 → 0.04" in seen["coefficient:infl_anchor"]["tooltip"], "An acquired extra parameter has no hidden baseline")
	for key in ["fiscal:annual_income", "fiscal:budget_retention", "reward:common", "reward:rare", "reward:legendary"]:
		_expect(not seen.has(key), "Unmodified fiscal/reward parameters do not occupy baseline effect slots")
	var formula := EconomyForecast.formulas(sim)
	_expect("0.36" in formula and "0.04 ×" in formula, "Formula substitutions include actual modified base and acquired extra parameters")


func _settle() -> void:
	for i in 5:
		await process_frame


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(capture_directory.path_join(filename)) == OK, "Screenshot saves")


func _test_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"arcadia")
	_expect(not ui._sidebar.visible and not ui._sidebar_button.button_pressed, "Sidebar starts hidden")
	ui._dispatch(Command.choose_reward([]))
	await _settle()
	var closed_width: float = ui._played_table.get_parent().size.x
	await _capture("fincard-forecast-collapsed.png")
	ui._sidebar_button.button_pressed = true
	await _settle()
	_expect(ui._sidebar.visible and ui._sidebar_button.text == "收起日志", "Display button opens the sidebar")
	_expect(ui._played_table.get_parent().size.x < closed_width, "Collapsed sidebar gives its space back to the table")
	_expect(root.get_visible_rect().encloses(ui._sidebar.get_global_rect()), "Expanded sidebar must fit the viewport")
	_expect(ui._log.size.y > 150 and ui._forecast.size.y > 100, "Forecast and history must both have usable space")
	var sim := controller.simulation
	var before := ui._forecast.text
	sim.state.hand.assign([&"arcadia_recover_open_market"])
	sim.state.political_capital = 20
	ui._dispatch(Command.play_card(&"arcadia_recover_open_market"))
	_expect(ui._forecast.text != before and ui._forecast.text == EconomyForecast.text(sim, controller.labels), "Playing a card immediately refreshes the forecast")
	before = ui._forecast.text
	sim._gain_aid(&"arcadia_aid_fireside")
	ui._dispatch(Command.use_aid(&"arcadia_aid_fireside"))
	_expect(ui._forecast.text != before, "Aid effects immediately refresh the forecast")
	sim._fire_event(&"arcadia_ev_inequality")
	ui._render()
	_expect("待完成" in ui._forecast.text, "Unresolved choices do not receive a misleading forecast")
	ui._dispatch(Command.resolve_event(0))
	_expect("下回合预测" in ui._forecast.text, "Resolving an event restores a current-state forecast")
	var lines := ui._log_lines.duplicate()
	ui._render()
	ui._sidebar_button.button_pressed = false
	ui._sidebar_button.button_pressed = true
	_expect(ui._log_lines == lines and ui._sidebar.visible, "Toggling or rendering never appends forecast spam to event history")
	var original_size := root.size
	root.size = Vector2i(1280, 800)
	await _settle()
	_expect(root.get_visible_rect().encloses(ui._sidebar.get_global_rect()), "Expanded sidebar fits at 1280x800")
	_expect(root.get_visible_rect().encloses(ui._end_turn_button.get_global_rect()), "Sidebar leaves actions accessible at 1280x800")
	var forecast_scroll: ScrollContainer = ui._forecast.get_parent().get_parent()
	_expect(forecast_scroll.size.y > 150 and forecast_scroll.get_global_rect().intersects(ui._forecast.get_global_rect()), "Forecast text must have a nonzero visible scroll viewport")
	await _capture("fincard-forecast-expanded.png")
	var parameter_button: Button = ui._parameters.get_parent().get_child(1)
	parameter_button.button_pressed = true
	await _settle()
	forecast_scroll.scroll_vertical = int(forecast_scroll.get_v_scroll_bar().max_value)
	await _settle()
	_expect(ui._parameters.is_visible_in_tree() and "数值边界" in ui._parameters.text, "Rules and numeric bounds are accessible in the sidebar")
	_expect(forecast_scroll.get_global_rect().intersects(ui._parameters.get_global_rect()), "Expanded parameter list is reachable by scrolling")
	await _capture("fincard-forecast-parameters.png")
	root.size = original_size
	ui.free()
	await process_frame


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_forecast()
	_test_parameters()
	await _test_ui()
	controller.free()
	print("FORECAST TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
