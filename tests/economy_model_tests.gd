extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _entry_count(sim: Simulation, key: String) -> int:
	var count := 0
	for entry in ModifierDisplay.entries(sim, controller.labels):
		if entry["key"] == key:
			count += 1
	return count


func _prepare(scenario: StringName = &"arcadia") -> Simulation:
	var sim := controller.simulation
	sim.start_run(scenario)
	sim.apply_command(Command.choose_reward([]))
	return sim


func _test_baseline() -> void:
	var expected: Array[StringName] = [&"gdp_auto", &"inflation_target", &"natural_unemployment"]
	for scenario in controller.scenarios:
		var sim := _prepare(scenario)
		_expect(sim.economy.base_coefficients.size() == 3, "The economy has exactly three default parameters")
		_expect(is_equal_approx(sim.economy.base_coefficients[&"gdp_auto"], 0.1), "Default potential growth is 0.1 per turn")
		for key in expected:
			_expect(sim.economy.base_coefficients.has(key) and _entry_count(sim, "coefficient:%s" % key) == 1, "Every base parameter is visible once")
		for key in sim.economy.scenario_coefficients:
			_expect(expected.has(key), "A scenario cannot silently restore retired base coefficients")
		_expect(ModifierDisplay.entries(sim, controller.labels).size() == 3, "Opening bar contains only the three default parameters, even with an innate growth modifier")
		_expect(sim.economy.coefficient(sim.state, &"infl_anchor") == 0 and sim.economy.coefficient(sim.state, &"u_revert") == 0, "Extra recovery effects have no default contribution")
		_expect(_entry_count(sim, "coefficient:infl_anchor") == 0 and _entry_count(sim, "coefficient:u_revert") == 0, "Unearned extra effects do not occupy slots")


func _test_equations() -> void:
	var sim := _prepare()
	# At GDP=128, confidence=70, rate=4 the simplified growth rate is 0.4.
	var forecast := sim.forecast_next_turn()
	sim.economy.tick(sim.state, sim.rng)
	_expect(is_equal_approx(sim.state.indicators[&"gdp"], 128 * 1.004), "GDP uses potential growth + confidence/100 - interest/10")
	_expect(is_equal_approx(sim.state.indicators[&"inflation"], 2.04), "Inflation follows its target and current growth")
	_expect(is_equal_approx(sim.state.indicators[&"unemployment"], 4.9), "Unemployment follows its natural level and growth")
	_expect(is_equal_approx(sim.state.indicators[&"confidence"], 70.4), "Confidence follows growth and deviation from the inflation target")
	for id in sim.economy.indicator_ids:
		_expect(is_equal_approx(sim.economy.value(sim.state, id), sim.economy.value(forecast, id)), "Prediction still matches simplified economic settlement")
	var formula := EconomyForecast.formulas(sim)
	_expect(not "额外" in formula and not "× (" in formula, "Unacquired extensions do not clutter the baseline formulas")


func _test_extensions() -> void:
	var sim := _prepare()
	sim._appoint_cabinet(&"arcadia_cab_agriculture")
	_expect(_entry_count(sim, "coefficient:infl_anchor") == 1, "A cabinet can add a fourth visible economic parameter")
	sim.state.indicators[&"inflation"] = 5
	var g := float(sim.economy.derived[&"growth"].call(sim.state, sim.economy))
	var delta := float(sim.economy.equations[&"inflation"].call(sim.state, sim.economy, sim.rng))
	_expect(is_equal_approx(delta, (2 - 5 + g) / 10 + 0.04 * (2 - 5)), "Agriculture adds recovery on top of the short baseline rule")
	_expect("0.04 ×" in EconomyForecast.formulas(sim), "Acquired recovery is included in the visible substituted formula")
	sim.state.hand.assign([&"arcadia_reform_labor_rights"])
	sim.state.budget = 100
	sim.state.political_capital = 100
	sim.apply_command(Command.play_card(&"arcadia_reform_labor_rights"))
	_expect(_entry_count(sim, "coefficient:u_revert") == 1, "A reform can add another economic extension")
	g = float(sim.economy.derived[&"growth"].call(sim.state, sim.economy))
	delta = float(sim.economy.equations[&"unemployment"].call(sim.state, sim.economy, sim.rng))
	_expect(is_equal_approx(delta, (6 - 5) / 10.0 - g / 2), "Extra employment recovery must not raise unemployment below the natural target")
	sim.state.indicators[&"unemployment"] = 8
	delta = float(sim.economy.equations[&"unemployment"].call(sim.state, sim.economy, sim.rng))
	_expect(is_equal_approx(delta, (6 - 8) / 10.0 - g / 2 - 0.02 * (8 - 6)), "Extra recovery lowers unemployment only above the natural target")
	_expect("0.02 ×" in EconomyForecast.formulas(sim), "Reform extension is visible in the formula")
	# Financial/reward extensions remain allowed, but only after being earned.
	sim._appoint_cabinet(&"arcadia_cab_braintrust")
	sim._appoint_cabinet(&"arcadia_cab_treasury")
	_expect(_entry_count(sim, "reward:rare") == 1 and _entry_count(sim, "fiscal:annual_income") == 1, "Earned fiscal/reward modifiers still appear")
	sim.state.modifiers.append(Modifier.new(&"u_revert", Modifier.Op.ADD, 0.03, 1, &"", &"coefficient"))
	_expect(_entry_count(sim, "coefficient:u_revert") == 1 and is_equal_approx(sim.economy.coefficient(sim.state, &"u_revert"), 0.05), "Additional effects merge by target and remain extensible")
	sim._advance_modifiers()
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"u_revert"), 0.02), "Expiring extension leaves the permanent reform intact")
	sim = _prepare()
	sim.state.modifiers.append(Modifier.new(&"infl_anchor", Modifier.Op.ADD, 0.04, 1, &"", &"coefficient"))
	sim._advance_modifiers()
	_expect(_entry_count(sim, "coefficient:infl_anchor") == 0, "An expired optional effect does not leave an empty baseline slot")
	_expect(ModifierDisplay.entries(sim, controller.labels).size() == 3, "Restart and expiry return to the compact three-parameter bar")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_baseline()
	_test_equations()
	_test_extensions()
	controller.free()
	print("ECONOMY MODEL TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
