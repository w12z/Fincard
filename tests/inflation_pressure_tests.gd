extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare() -> Simulation:
	controller.start_run(&"example_country")
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.modifiers.clear()
	sim.state.budget = 30
	sim.state.indicators.merge({&"gdp": 100.0, &"inflation": 2.0, &"confidence": 70.0,
		&"unemployment": 6.0, &"interest_rate": 3.0}, true)
	var base := float(sim.economy.scenario_coefficients.get(&"gdp_auto", sim.economy.base_coefficients[&"gdp_auto"]))
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.ADD, 2.6 - base, -1, &"test potential", &"coefficient"))
	sim.economy.refresh_derived(sim.state)
	return sim


func _test_drag_and_boundaries() -> void:
	var sim := _prepare()
	for pair in [[-2, 0.4], [0, 0], [2, 0], [4, 0], [6, 0.3], [8, 0.6]]:
		sim.state.indicators[&"inflation"] = float(pair[0])
		var drag := EconomyBuilder.inflation_growth_drag(sim.state, sim.economy)
		_expect(is_equal_approx(drag, float(pair[1])), "Price drag matches the agreed rate at inflation %s" % pair[0])
		sim.economy.refresh_derived(sim.state)
		_expect(is_equal_approx(sim.economy.value(sim.state, &"growth"), 3.0 - float(pair[1])), "Price pressure reduces actual growth, not the positive modifiers")
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), 2.6), "Price drag never destroys potential-growth buffs")
	sim.state.indicators[&"inflation"] = 200
	sim.economy.refresh_derived(sim.state)
	_expect(sim.economy.value(sim.state, &"growth") == -8, "The final growth clamp still applies after price drag")


func _test_target_shifts_band() -> void:
	var sim := _prepare()
	sim.state.modifiers.append(Modifier.new(&"inflation_target", Modifier.Op.ADD, 2.0, -1, &"target", &"coefficient"))
	for pair in [[0, 0.4], [2, 0], [4, 0], [6, 0], [8, 0.3]]:
		sim.state.indicators[&"inflation"] = float(pair[0])
		_expect(is_equal_approx(EconomyBuilder.inflation_growth_drag(sim.state, sim.economy), float(pair[1])), "Safe band follows a modified inflation target")


func _test_inflation_equation_and_forecast() -> void:
	var sim := _prepare()
	var equation: Callable = sim.economy.equations[&"inflation"]
	_expect(is_equal_approx(float(equation.call(sim.state, sim.economy, sim.rng.snapshot())), 0.45), "Three-percent growth contributes 0.45 inflation at target")
	sim.state.indicators[&"inflation"] = 8
	sim.economy.refresh_derived(sim.state)
	_expect(is_equal_approx(float(equation.call(sim.state, sim.economy, sim.rng.snapshot())), -0.24), "Inflation uses actual growth after drag, not growth before drag")
	var formula := EconomyForecast.formulas(sim)
	_expect(formula.contains("物价拖累") and formula.contains("0.15") and formula.contains("0.20") and formula.contains("1.5 ×"), "Visible formula explains both new inflation channels")
	var before := sim.state.snapshot()
	var preview := sim.forecast_next_turn()
	_expect(sim.state.indicators == before.indicators, "Preview does not apply real inflation damage")
	sim.apply_command(Command.end_turn())
	for id in sim.economy.indicator_ids + sim.economy.derived_ids:
		_expect(is_equal_approx(sim.economy.value(sim.state, id), sim.economy.value(preview, id)), "Predicted and actual economic values match: %s" % id)
	_expect(is_equal_approx(sim.state.indicators[&"gdp"], 102.4), "GDP uses the same 2.4-percent actual growth")
	_expect(is_equal_approx(sim.state.indicators[&"unemployment"], 5.7), "Employment uses the same actual growth with the existing quarter-strength gain")
	_expect(is_equal_approx(sim.state.indicators[&"confidence"], 70), "Existing inflation confidence penalty is not strengthened a second time")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_drag_and_boundaries()
	_test_target_shifts_band()
	_test_inflation_equation_and_forecast()
	controller.free()
	await process_frame
	print("INFLATION PRESSURE TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
