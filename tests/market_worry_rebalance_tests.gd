extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare(turn: int = 9) -> Simulation:
	controller.start_run(&"arcadia")
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.turn = turn
	sim.state.turn_in_year = (turn - 1) % 8 + 1
	sim.state.year = ceili(turn / 8.0)
	sim.state.indicators[&"gdp"] = 200
	sim.state.indicators[&"confidence"] = 90
	sim.state.indicators[&"unemployment"] = 5
	sim.state.indicators[&"inflation"] = 2
	sim._activate_market_worry()
	return sim


func _test_independent_conditions() -> void:
	for entry in [[89, 0.999, 0], [89, 1.0, 1], [90, 0.2, 1], [90, 1.0, 2]]:
		var sim := _prepare()
		var worry := StatusRules.find_modifier(sim.state, &"market_worry")
		sim.state.indicators[&"confidence"] = int(entry[0])
		sim._settle_market_worry(float(entry[1]))
		_expect(worry.stacks == int(entry[2]), "Each qualifying condition adds one independent layer")
		sim._settle_market_worry(8.0)
		_expect(worry.stacks == int(entry[2]), "A repeated settlement call in the same turn cannot add more layers")
	var sim := _prepare()
	var worry := StatusRules.find_modifier(sim.state, &"market_worry")
	worry.stacks = 15
	sim._settle_market_worry(2.0)
	_expect(worry.stacks == 16, "Two new layers cannot exceed the sixteen-layer cap")
	sim.state.turn = 10
	sim._settle_market_worry(2.0)
	_expect(worry.stacks == 16, "A full worry modifier does not keep accumulating")
	sim = _prepare()
	worry = StatusRules.find_modifier(sim.state, &"market_worry")
	for turn in range(9, 17):
		sim.state.turn = turn
		sim._settle_market_worry(1.0)
	_expect(worry.stacks == 16, "Both conditions across all eight eligible turns reach sixteen layers")
	sim.state.turn = 17
	sim._settle_market_worry(8.0)
	_expect(worry.stacks == 16, "No layers accumulate after turn sixteen")
	sim = _prepare(8)
	_expect(StatusRules.find_modifier(sim.state, &"market_worry") == null, "Worry does not begin before turn nine")


func _test_crash_values_and_ui() -> void:
	for layers in [0, 1, 8, 16]:
		var sim := _prepare(16)
		var worry := StatusRules.find_modifier(sim.state, &"market_worry")
		worry.stacks = layers
		var definition: EconomyEventDef = controller.events[&"arcadia_ev_black_thursday"]
		var effects := sim.event_effects(definition.effects)
		_expect(effects[0].params["amount"] == -8 - 3 * layers, "GDP shock keeps the base loss and scales with all sixteen layers")
		_expect(effects[1].params["amount"] == -16 - 3 * layers, "Confidence shock keeps the base loss and scales with all sixteen layers")
		_expect(effects[2].params["amount"] == 16 and effects[3].params["amount"] == 8, "First-wave unemployment increases sixteen points and inflation rises eight points")
		if layers == 16:
			for item in ModifierDisplay.entries(sim, controller.labels):
				if item["key"] == "special:market_worry":
					_expect(item["tooltip"].contains("GDP -48%") and item["tooltip"].contains("信心 -48"), "Worry tooltip shows doubled maximum extra damage")
			sim._fire_event(definition.id)
			_expect(sim.event_choice_available(-1) and worry.stacks == 16, "Crisis preview cannot consume actual worry")
			sim.apply_command(Command.resolve_event(-1))
			_expect(is_equal_approx(float(sim.state.indicators[&"gdp"]), 88.0), "Sixteen-layer crisis causes 56 percent total GDP loss")
			_expect(is_equal_approx(float(sim.state.indicators[&"confidence"]), 26.0), "Sixteen-layer crisis causes 64 total confidence loss, without recursively applying collapse")
			_expect(sim.state.indicators[&"unemployment"] == 21 and sim.state.indicators[&"inflation"] == 10, "First-wave shocks increase unemployment and inflation exactly once")
			_expect(StatusRules.find_modifier(sim.state, &"market_worry") == null, "Worry is consumed after the crisis")
			_expect(StatusRules.find_modifier(sim.state, &"confidence_crash") != null, "The staged confidence-collapse aftermath remains intact")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_independent_conditions()
	_test_crash_values_and_ui()
	controller.free()
	await process_frame
	print("MARKET WORRY REBALANCE TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
