extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare(turn: int = 16) -> Simulation:
	controller.start_run(&"arcadia")
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.turn = turn
	sim.state.turn_in_year = (turn - 1) % 8 + 1
	sim.state.year = ceili(turn / 8.0)
	sim.state.indicators[&"gdp"] = 120
	sim.state.indicators[&"confidence"] = 90
	sim.state.indicators[&"unemployment"] = 5
	sim.state.indicators[&"inflation"] = 2
	return sim


func _grant_crash(sim: Simulation) -> Modifier:
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
		"scope": "special", "target": "confidence_crash", "duration": -1,
	}}), sim.state, sim.rng)
	return StatusRules.find_modifier(sim.state, &"confidence_crash")


func _test_crash_clears_only_temporary_growth() -> void:
	var sim := _prepare()
	var temporary := Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.625, 3, &"project", &"coefficient")
	var permanent := Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.12, -1, &"reform", &"coefficient")
	var negative := Modifier.new(&"gdp_auto", Modifier.Op.ADD, -0.3, 4, &"old-debuff", &"coefficient")
	var interest := Modifier.new(&"interest_rate", Modifier.Op.ADD, -1, 2, &"bonds")
	var multiplier := Modifier.new(&"gdp_auto", Modifier.Op.MUL, 1.2, 3, &"boost", &"coefficient")
	var negative_multiplier := Modifier.new(&"gdp_auto", Modifier.Op.MUL, 0.9, 3, &"drag", &"coefficient")
	sim.state.modifiers.append_array([temporary, permanent, negative, interest, multiplier, negative_multiplier])
	var base := sim.economy.base_coefficients.duplicate()
	sim._fire_event(&"arcadia_ev_black_thursday")
	var definition: EconomyEventDef = controller.events[&"arcadia_ev_black_thursday"]
	var text := TextFormatter.effects_text(controller.labels, sim.event_effects(definition.effects))
	_expect(text.contains("限期正向潜在增长修正") and text.contains("保留永久加成"), "Crisis text describes the selective growth purge")
	_expect(sim.event_choice_available(-1) and sim.state.modifiers.has(temporary), "Affordability preview cannot clear live growth buffs")
	sim.apply_command(Command.resolve_event(-1))
	_expect(not sim.state.modifiers.has(temporary) and not sim.state.modifiers.has(multiplier), "The actual crash clears positive temporary growth")
	_expect(sim.state.modifiers.has(permanent) and sim.state.modifiers.has(negative) and sim.state.modifiers.has(negative_multiplier), "Permanent growth and negative modifiers survive")
	_expect(sim.state.modifiers.has(interest) and sim.economy.base_coefficients == base, "Interest effects and base growth are untouched")
	_expect(StatusRules.find_modifier(sim.state, &"confidence_crash") != null, "Crash still grants the negative-growth confidence debuff")
	var shock := false
	for modifier in sim.state.modifiers:
		if modifier.source == &"股灾余波":
			shock = is_equal_approx(modifier.value, -0.6) and modifier.remaining_turns == 6
	_expect(shock, "Crash retains its six-turn negative growth aftermath")


func _test_credit_freeze() -> void:
	var sim := _prepare(20)
	var rebuilt := Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.4, 3, &"rebuilt", &"coefficient")
	sim.state.modifiers.append(rebuilt)
	sim._fire_event(&"arcadia_ev_credit_freeze")
	sim.apply_command(Command.resolve_event(-1))
	_expect(sim.state.indicators[&"confidence"] == 78, "Credit freeze loses twelve confidence instead of six")
	_expect(sim.state.indicators[&"unemployment"] == 10, "Credit freeze unemployment shock remains five")
	_expect(is_equal_approx(sim.state.indicators[&"gdp"], 120 * 0.93), "Credit freeze GDP loss remains seven percent")
	_expect(sim.state.modifiers.has(rebuilt), "Credit freeze does not purge newly rebuilt growth buffs")


func _test_crash_strength_boundaries() -> void:
	var sim := _prepare(17)
	var modifier := _grant_crash(sim)
	for pair in [[17, -4.0], [23, -4.0], [24, -2.0], [31, -2.0], [32, 0.0], [40, 0.0]]:
		sim.state.turn = int(pair[0])
		_expect(is_equal_approx(EconomyBuilder.special_confidence_delta(sim.state, -2), float(pair[1])), "Confidence penalty follows the 24/32 boundaries: %d" % sim.state.turn)
		_expect(is_zero_approx(EconomyBuilder.special_confidence_delta(sim.state, 1)), "Positive growth never incurs a collapse penalty")
	sim.state.turn = 23
	var snapshot := sim.state.snapshot()
	sim.forecast_next_turn()
	_expect(not modifier.data.get("weakened", false) and sim.state.turn == snapshot.turn, "Forecast cannot weaken the live modifier early")
	sim._start_turn()
	_expect(sim.state.turn == 24 and modifier.data.get("weakened", false), "Weakening becomes visible at the start of turn twenty-four")
	var tooltip := ""
	for entry in ModifierDisplay.entries(sim, controller.labels):
		if entry["key"] == "special:confidence_crash":
			tooltip = entry["tooltip"]
	_expect(tooltip.contains("降低1信心") and tooltip.contains("已减半") and tooltip.contains("第32回合开始时移除") and not tooltip.contains("永久"), "Tooltip shows current strength and expiry, not a permanent penalty")
	sim.state.turn = 31
	sim._start_turn()
	_expect(sim.state.turn == 32 and StatusRules.find_modifier(sim.state, &"confidence_crash") == null, "Turn thirty-two actually removes the modifier before actions")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_crash_clears_only_temporary_growth()
	_test_credit_freeze()
	_test_crash_strength_boundaries()
	controller.free()
	await process_frame
	print("CRISIS REBALANCE TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
