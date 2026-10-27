extends SceneTree

var failures: int = 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare() -> Simulation:
	var sim := controller.simulation
	sim.start_run(&"example_country")
	_expect(sim.state.turn == 0 and sim.state.budget == 0, "Resources must wait until appointments finish")
	sim.apply_command(Command.choose_reward([]))
	return sim


func _play(sim: Simulation, id: StringName) -> void:
	sim.state.hand.assign([id])
	sim.state.political_capital = 100
	_expect(not sim.apply_command(Command.play_card(id)).is_empty(), "Fiscal card should play: %s" % id)


func _next_year(sim: Simulation) -> void:
	sim.state.turn_in_year = int(sim.rules["turns_per_year"])
	sim._end_year()
	_expect(not sim.state.pending_rewards.is_empty(), "Year end offers rewards, not budgets")
	sim.apply_command(Command.choose_reward([]))


func _test_political_reset() -> void:
	var sim := _prepare()
	var original := int(sim.rules["political_capital_per_turn"])
	sim.rules["political_capital_per_turn"] = 4
	for previous in [0, 2, 40, -3]:
		sim.state.political_capital = previous
		var forecast := sim.forecast_next_turn()
		var events := sim.apply_command(Command.end_turn())
		_expect(sim.state.political_capital == 4 and forecast.political_capital == 4, "Each turn resets to the parameter, whether exhausted, unspent, boosted or negative; forecast agrees")
		var found := false
		for event in events:
			if event.kind == Event.Kind.RESOURCE_CHANGED and event.params.get("resource") == &"political_capital":
				found = int(event.params["amount"]) == 4 - previous
		_expect(found, "Reset reports the actual balance delta, not an additive grant")
	sim.state.modifiers.append(Modifier.new(&"political_capital_gain", Modifier.Op.ADD, 2, -1))
	sim.state.political_capital = 99
	sim.apply_command(Command.end_turn())
	_expect(sim.state.political_capital == 6 and sim.political_capital_per_turn() == 6, "Per-turn modifiers change the reset target, not the carried balance")
	sim.state.modifiers.clear()
	sim.state.modifiers.append(Modifier.new(&"political_capital_gain", Modifier.Op.ADD, 2, 1))
	sim.apply_command(Command.end_turn())
	_expect(sim.state.political_capital == 4, "Expired modifiers stop contributing to the next reset")
	sim.rules["political_capital_per_turn"] = 0
	sim.state.political_capital = 20
	sim.apply_command(Command.end_turn())
	if not sim.state.pending_rewards.is_empty():
		sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.political_capital == 0, "A zero target still clears leftover political points, including across years")
	sim.rules["political_capital_per_turn"] = original
	sim = _prepare()
	sim._appoint_cabinet(&"arcadia_cab_fed")
	sim.state.political_capital = 99
	_next_year(sim)
	_expect(sim.state.political_capital == original + 3, "Annual cabinet bonus is applied after the reset and is usable that turn")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.political_capital == original, "Annual bonus and leftovers do not carry to the next turn")
	sim._gain_aid(&"arcadia_aid_foreign_loan")
	sim.apply_command(Command.use_aid(&"arcadia_aid_foreign_loan"))
	_expect(sim.state.political_capital == original + 2, "One-shot aid still grants usable points in the current turn")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.political_capital == original, "One-shot aid points are not inherited by the next turn")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	controller.scenarios[&"example_country"].goal.deadline_years = 20
	_test_political_reset()
	var sim := _prepare()
	_expect(sim.state.budget == 32 and sim.state.political_capital == 3, "Opening receives country income and the normal per-turn political reset")
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.budget == 32, "Repeated reward command must not pay twice")
	sim.state.budget = 11
	sim.state.political_capital = 99
	_next_year(sim)
	_expect(sim.state.budget == 37 and sim.state.political_capital == 3, "Year rollover floors 50% of budget and resets political capital like any other turn")
	_play(sim, &"reform_budget_reserve")
	_expect(is_equal_approx(sim.budget_retention(), 0.75), "Reform raises retention")
	sim.state.budget = 12
	_next_year(sim)
	_expect(sim.state.budget == 41, "Modified retention affects next rollover")
	sim = _prepare()
	_play(sim, &"reform_fiscal_capacity")
	_expect(sim.annual_income() == 38 and sim.state.budget == 29, "Permanent income reform must not immediately pay income")
	sim._appoint_cabinet(&"example_cabinet")
	_expect(sim.annual_income() == 41, "Cabinet adds to annual income")
	sim._gain_aid(&"temporary_fiscal_support")
	sim.apply_command(Command.use_aid(&"temporary_fiscal_support"))
	_expect(sim.annual_income() == 47 and sim.state.budget == 29, "Temporary support affects future payments, not current cash")
	for i in 12:
		sim._advance_modifiers()
	_expect(sim.annual_income() == 47, "Fiscal support must not expire per turn")
	sim.state.budget = 0
	_next_year(sim)
	_expect(sim.state.budget == 47 and sim.annual_income() == 47, "First temporary income payment")
	sim.state.budget = 0
	_next_year(sim)
	_expect(sim.state.budget == 47 and sim.annual_income() == 41, "Second temporary payment expires support after paying")
	sim.state.budget = 0
	_next_year(sim)
	_expect(sim.state.budget == 41, "Temporary support must not pay a third time")
	sim = _prepare()
	sim.state.budget = 0
	sim.state.hand.assign([&"starter_infrastructure"])
	_expect(sim.apply_command(Command.play_card(&"starter_infrastructure")).is_empty(), "No overdraft before reform")
	_play(sim, &"reform_deficit_spending")
	_play(sim, &"starter_infrastructure")
	_expect(sim.state.budget == -4, "Deficit reform allows card overdraft")
	sim._fire_event(&"starter_supply")
	_expect(sim.event_choice_available(0) and sim.event_choice_available(1), "Paid and free events remain usable in deficit")
	sim.apply_command(Command.resolve_event(0))
	_expect(sim.state.budget == -6, "Paid event spends into deficit")
	sim._fire_event(&"starter_supply")
	sim.apply_command(Command.resolve_event(1))
	_expect(sim.state.pending_event == &"", "Free option cannot trap a player in deficit")
	_play(sim, &"arcadia_reform_austerity")
	_expect(sim.state.budget == -3, "Zero-budget income cards remain usable in deficit")
	sim.state.hand.assign([&"starter_infrastructure"])
	sim.state.political_capital = 0
	_expect(sim.apply_command(Command.play_card(&"starter_infrastructure")).is_empty(), "Deficit must not waive political cost")
	sim.state.budget = -11
	_next_year(sim)
	_expect(sim.state.budget == 21, "Deficit carries in full without retention or floor rounding before annual income")
	sim = _prepare()
	_expect(not StatusRules.allows_deficit(sim.state, sim.status_db) and sim.annual_income() == 32 and sim.budget_retention() == 0.5, "Restart clears fiscal reforms and temporary support")
	# An opening cabinet must affect the very first payment, once only.
	sim.start_run(&"example_country")
	sim._appoint_cabinet(&"example_cabinet")
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.budget == 35, "Opening appointment contributes to first-year income exactly once")
	sim = _prepare()
	for i in 7:
		sim.apply_command(Command.end_turn())
	_expect(sim.state.year == 1 and sim.state.turn == 8 and sim.state.pending_rewards.is_empty(), "First seven settlements stay within the eight-turn year")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.turn == 8 and not sim.state.pending_rewards.is_empty(), "Eighth settlement opens annual preparation")
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.year == 2 and sim.state.turn == 9 and sim.state.turn_in_year == 1, "Ninth turn starts the second fiscal year")
	await _test_ui()
	controller.free()
	print("FISCAL TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	_play(sim, &"reform_deficit_spending")
	sim.state.budget = -5
	sim.state.hand.assign([&"starter_infrastructure"])
	ui._render()
	await process_frame
	var button: Button = ui._hand_box.get_child(0)
	_expect(not button.disabled, "Hand UI must allow paid cards in deficit")
	button.pressed.emit()
	_expect(sim.state.budget == -9, "Actual UI play spends into deficit")
	for i in 4:
		await process_frame
	ui.free()
