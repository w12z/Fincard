extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare(growth: float, confidence: float = 50.0) -> Simulation:
	controller.start_run(&"example_country")
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.modifiers.clear()
	sim.state.indicators[&"gdp"] = 100
	sim.state.indicators[&"confidence"] = confidence
	sim.state.indicators[&"inflation"] = 2
	sim.state.indicators[&"unemployment"] = 6
	sim.state.indicators[&"interest_rate"] = 3
	var potential := growth - confidence / 100.0 + 3.0 / 10.0
	var base := float(sim.economy.scenario_coefficients.get(&"gdp_auto", sim.economy.base_coefficients[&"gdp_auto"]))
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.ADD, potential - base, -1, &"test growth", &"coefficient"))
	sim.economy.refresh_derived(sim.state)
	return sim


func _delta(sim: Simulation, id: StringName) -> float:
	return float(sim.economy.equations[id].call(sim.state, sim.economy, sim.rng.snapshot()))


func _test_positive_growth() -> void:
	var sim := _prepare(2.0)
	_expect(is_equal_approx(_delta(sim, &"confidence"), 1.0), "Two-percent growth now adds one confidence rather than two")
	_expect(is_equal_approx(_delta(sim, &"unemployment"), -0.25), "Two-percent growth now reduces unemployment by 0.25 rather than one")
	_expect(is_equal_approx(_delta(sim, &"gdp"), 2.0), "GDP gains are not reduced")
	_expect(is_equal_approx(_delta(sim, &"inflation"), 0.2), "Inflation formula remains unchanged")
	var formula := EconomyForecast.formulas(sim)
	_expect(formula.contains("Δ失业率 = (6 − 6) / 10 − 2 / 8") and formula.contains("Δ信心 = 2 / 2"), "Forecast explains the reduced positive-growth contributions")


func _test_negative_growth() -> void:
	var sim := _prepare(-2.0)
	_expect(is_equal_approx(_delta(sim, &"confidence"), -2.0), "Negative-growth confidence damage is not halved")
	_expect(is_equal_approx(_delta(sim, &"unemployment"), 1.0), "Negative-growth unemployment damage is not quartered")
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
		"scope": "special", "target": "confidence_crash", "duration": -1,
	}}), sim.state, sim.rng)
	sim.state.turn = 20
	_expect(is_equal_approx(_delta(sim, &"confidence"), -6.0), "Original confidence collapse penalty remains a separate additional effect")
	sim.state.turn = 24
	_expect(is_equal_approx(_delta(sim, &"confidence"), -4.0), "The reduced collapse penalty still applies from turn twenty-four")


func _test_low_confidence() -> void:
	for pair in [[60, 0.0], [50, 0.0], [49, -0.1], [40, -1.0], [30, -2.0]]:
		var sim := _prepare(0, float(pair[0]))
		_expect(is_equal_approx(_delta(sim, &"confidence"), float(pair[1])), "Below-fifty confidence penalty is linear and absent above fifty: %d" % pair[0])
	var sim := _prepare(0, 40)
	var old_confidence := float(sim.state.indicators[&"confidence"])
	var preview := sim.forecast_next_turn()
	_expect(is_equal_approx(sim.state.indicators[&"confidence"], old_confidence), "Forecast never applies the real low-confidence penalty")
	sim.apply_command(Command.end_turn())
	_expect(is_equal_approx(sim.state.indicators[&"confidence"], 39.0), "The forty-confidence penalty is applied once, not recursively")
	_expect(is_equal_approx(sim.state.indicators[&"confidence"], preview.indicators[&"confidence"]), "Predicted confidence matches actual settlement")
	_expect(EconomyForecast.formulas(sim).contains("max(50 − 39, 0) × 0.1"), "Forecast includes the low-confidence spiral term")


func _test_special_boom_bonus_unchanged() -> void:
	var sim := _prepare(2, 70)
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
		"scope": "special", "target": "stock_market_frenzy", "duration": -1,
	}}), sim.state, sim.rng)
	_expect(is_equal_approx(_delta(sim, &"confidence"), 7), "Stock frenzy still adds its independent six-point bonus to the reduced one-point growth gain")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_positive_growth()
	_test_negative_growth()
	_test_low_confidence()
	_test_special_boom_bonus_unchanged()
	controller.free()
	await process_frame
	print("GROWTH FEEDBACK TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
