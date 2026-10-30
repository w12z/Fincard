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
	controller.start_run(scenario)
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.budget = 50
	sim.state.political_capital = 20
	return sim


func _find(nodes: Array, key: String) -> Dictionary:
	for node: Dictionary in nodes:
		if node["key"] == key:
			return node
	for node: Dictionary in nodes:
		var found := _find(node["children"], key)
		if not found.is_empty():
			return found
	return {}


func _check_sums(nodes: Array) -> void:
	for node: Dictionary in nodes:
		var count := 0
		var sum := 0.0
		for child: Dictionary in node["children"]:
			if not child.get("context", false):
				count += 1
				sum += float(child["value"])
		if count > 0:
			_expect(is_equal_approx(sum, float(node["value"])), "Children sum to the displayed total: %s (%s / %s)" % [node["key"], sum, node["value"]])
		_check_sums(node["children"])


func _check(sim: Simulation) -> Array[Dictionary]:
	var indicators := sim.state.indicators.duplicate(true)
	var flags := sim.state.flags.duplicate(true)
	var deck := sim.state.deck.duplicate()
	var hand := sim.state.hand.duplicate()
	var discard := sim.state.discard.duplicate()
	var budget := sim.state.budget
	var political := sim.state.political_capital
	var rng := sim.rng.snapshot().next_int(1_000_000)
	var modifier_data: Array = []
	for modifier in sim.state.modifiers:
		modifier_data.append([modifier.remaining_turns, modifier.stacks, modifier.data.duplicate(true)])
	var next := sim.forecast_next_turn()
	var nodes := EconomyCalculation.branches(sim, next)
	var graph := EconomyDependencyGraph.build(sim, next)
	var ids := {}
	for node: Dictionary in graph["nodes"]:
		ids[node["id"]] = true
		_expect(node["id"] not in ["budget", "next_budget", "political", "political_capital", "annual_income"] and node["kind"] != "resource", "The diagram excludes budget, political points and fiscal transitions")
		for id in [&"gdp", &"inflation", &"unemployment", &"confidence"]:
			if node["id"] == "next_" + String(id):
				var expected := "%s → %s" % [TextFormatter.fmt(sim.economy.value(sim.state, id)), TextFormatter.fmt(sim.economy.value(next, id))]
				_expect(node["value"] == expected, "Simplifying the diagram preserves the actual economic forecast")
	for edge: Dictionary in graph["edges"]:
		_expect(ids.has(edge["from"]) and ids.has(edge["to"]), "Removing fiscal nodes leaves no dangling connections")
	_check_sums(nodes)
	for node in nodes:
		if node.has("indicator"):
			var id := StringName(node["indicator"])
			var future := sim.economy.value(next, id) if id not in [&"budget", &"political_capital"] else float(next.budget if id == &"budget" else next.political_capital)
			_expect(is_equal_approx(future, float(node["future"])) and is_equal_approx(future - float(node["current"]), float(node["value"])), "Tree final value and delta match authoritative forecast: %s" % id)
	_expect(sim.state.indicators == indicators and sim.state.flags == flags and sim.state.budget == budget and sim.state.political_capital == political, "Breakdown never mutates live values or trigger flags")
	_expect(sim.state.deck == deck and sim.state.hand == hand and sim.state.discard == discard and sim.rng.snapshot().next_int(1_000_000) == rng, "Breakdown never draws live cards or consumes live RNG")
	for index in sim.state.modifiers.size():
		var modifier: Modifier = sim.state.modifiers[index]
		_expect([modifier.remaining_turns, modifier.stacks, modifier.data] == modifier_data[index], "Breakdown never advances modifier durations or replay queues")
	_expect(EconomyForecast.from_state(sim, controller.labels, next, false) == EconomyForecast.text(sim, controller.labels, false), "Summary reuses the same forecast snapshot without changing output")
	return nodes


func _test_arithmetic() -> void:
	for scenario in [&"arcadia", &"example_country"]:
		var sim := _prepare(scenario)
		var nodes := _check(sim)
		_expect(not _find(nodes, "growth_now").is_empty() and not _find(nodes, "growth_next").is_empty(), "Current settlement and next-turn growth are separate")
		var growth := sim.economy.coefficient(sim.state, &"gdp_auto") + sim.economy.value(sim.state, &"confidence") / 100.0 - sim.economy.value(sim.state, &"interest_rate") / 10.0
		_expect(is_equal_approx(float(_find(nodes, "growth_now")["value"]), growth), "Baseline growth terms match effective inputs")
	var sim := _prepare()
	sim.state.indicators[&"confidence"] = 30
	sim.state.indicators[&"inflation"] = 12
	sim.state.indicators[&"unemployment"] = 18
	sim.state.budget = -10
	sim.state.turn = 24
	sim.state.turn_in_year = 8
	sim.state.year = 3
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {"scope": "special", "target": "confidence_crash", "duration": -1}}), sim.state, sim.rng)
	sim._appoint_cabinet(&"arcadia_cab_agriculture")
	sim.state.modifiers.append(Modifier.new(&"u_revert", Modifier.Op.ADD, 0.02, -1, &"劳工权利法", Modifier.SCOPE_COEFFICIENT))
	var nodes := _check(sim)
	_expect(is_equal_approx(float(_find(_find(nodes, "confidence")["children"], "low")["value"]), -1.0), "Low-confidence spiral shows the halved actual penalty")
	_expect(is_equal_approx(float(_find(nodes, "deficit")["value"]), -2.0), "Deficit penalty is shown independently")
	_expect(not _find(nodes, "anchor").is_empty() and not _find(nodes, "extra").is_empty(), "Acquired reversion coefficients have their own branches")
	sim = _prepare()
	sim.state.indicators[&"confidence"] = 99.9
	sim.state.indicators[&"unemployment"] = 0.5
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.ADD, 100, -1, &"增长测试", Modifier.SCOPE_COEFFICIENT))
	nodes = _check(sim)
	_expect(is_equal_approx(float(_find(nodes, "growth_now")["value"]), 8.0), "Growth cap is reflected in the calculation")
	_expect(not _find(_find(nodes, "confidence")["children"], "bounds").is_empty(), "Confidence clamp is not attributed to cabinet effects")
	sim = _prepare()
	sim.state.indicators[&"inflation"] = -4
	sim.state.modifiers.append(Modifier.new(&"gdp_auto", Modifier.Op.MUL, 1.5, 1, &"乘法来源", Modifier.SCOPE_COEFFICIENT))
	sim.state.modifiers.append(Modifier.new(&"interest_rate", Modifier.Op.ADD, -100, 1, &"降息来源"))
	nodes = _check(sim)
	_expect(float(_find(_find(nodes, "growth_now")["children"], "low")["value"]) < 0, "Deflation contributes its own growth drag")


func _test_later_stages() -> void:
	var sim := _prepare()
	sim.state.turn = 8
	sim.state.turn_in_year = 8
	sim.state.budget = 11
	sim._appoint_cabinet(&"example_cabinet")
	sim._appoint_cabinet(&"arcadia_cab_fed")
	sim._appoint_cabinet(&"arcadia_cab_labor")
	sim._appoint_cabinet(&"arcadia_cab_treasury")
	var nodes := _check(sim)
	_expect(float(_find(nodes, "retention")["value"]) == -6 and float(_find(nodes, "annual_income")["value"]) == 34, "Annual rounding and earned fiscal income are explicit")
	_expect(float(_find(_find(nodes, "budget")["children"], "later")["value"]) == 1, "Irene's budget trigger is separate from annual income")
	_expect(float(_find(_find(nodes, "confidence")["children"], "later")["value"]) == 1, "Vera's confidence is separate from the economic equation")
	_expect(_find(_find(nodes, "confidence")["children"], "cabinet_example_cabinet_0").is_empty(), "Budget-only cabinet is not attributed to confidence")
	sim = _prepare()
	sim._appoint_cabinet(&"cabinet_rowan")
	sim.state.hand.append(&"arcadia_relief_dole")
	sim.apply_command(Command.play_card(&"arcadia_relief_dole"))
	nodes = _check(sim)
	_expect(float(_find(_find(nodes, "confidence")["children"], "later")["value"]) == 5, "Last-card automatic play is included only in later settlement")
	sim = _prepare()
	sim.state.turn = 40
	sim.state.turn_in_year = 8
	sim.state.year = 5
	nodes = _check(sim)
	_expect(_find(nodes, "growth_next").is_empty() and float(_find(nodes, "political_capital")["value"]) == 0, "A final settlement does not invent next-turn resets")


func _settle(ui: GameUI) -> void:
	while ui._pile_motion_active or ui._settlement_active or ui._flight_active:
		await process_frame
	for frame in 5:
		await process_frame


func _edge_exists(graph: Dictionary, from: String, to: String) -> bool:
	for edge: Dictionary in graph["edges"]:
		if edge["from"] == from and edge["to"] == to:
			return true
	return false


func _test_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"arcadia")
	ui._dispatch(Command.choose_reward([]))
	await _settle(ui)
	var view := ui._calculation_map
	_expect(view.open_button.global_position.y >= ui._forecast.get_global_rect().end.y, "Large graph entry is below the forecast summary")
	_expect(not view.overlay.visible and not view.open_button.disabled, "Diagram starts as an entry, not a cramped sidebar table")
	view.open_button.pressed.emit()
	await _settle(ui)
	_expect(view.overlay.visible and view._viewport.size.x > root.size.x * 0.85 and view._viewport.size.y > root.size.y * 0.7, "Dependency graph occupies a large dedicated canvas")
	var graph := view.canvas.graph
	for source in ["potential", "confidence", "interest", "drag"]:
		_expect(_edge_exists(graph, source, "growth"), "Shared growth dependencies are drawn as connected nodes: %s" % source)
	for result in ["next_gdp", "next_inflation", "next_unemployment", "next_confidence"]:
		_expect(_edge_exists(graph, "growth", result), "Growth branches to all dependent results: %s" % result)
	_expect(_edge_exists(graph, "inflation", "drag") and _edge_exists(graph, "inflation", "next_confidence"), "Inflation's multiple dependency paths are explicit")
	_expect(_edge_exists(graph, "next_confidence", "growth_next") and _edge_exists(graph, "next_inflation", "growth_next"), "Feedback into the following growth rate is a separate forward-only layer")
	var forecast := controller.simulation.forecast_next_turn()
	_expect(view.canvas.cards["growth_next"].tooltip_text.contains(TextFormatter.fmt(controller.simulation.economy.value(forecast, &"growth"))), "Graph's next-turn growth matches the forecast, not the current growth hub")
	var rects: Array[Rect2] = []
	for node: Dictionary in graph["nodes"]:
		_expect(Rect2(Vector2.ZERO, EconomyDependencyGraph.SIZE).encloses(node["rect"]), "Nodes fit the diagram's logical canvas")
		for rect in rects:
			_expect(not rect.intersects(node["rect"]), "Diagram nodes must not overlap")
		rects.append(node["rect"])
	var builds := ui._forecast_build_count
	var card: Button = view.canvas.cards["growth"]
	ui._render()
	_expect(builds == ui._forecast_build_count and card == view.canvas.cards["growth"], "Idle redraw reuses the graph")
	view.canvas.focus_node("interest")
	_expect(view.canvas._related.has("growth") and view.canvas._related.has("next_gdp") and not view.canvas._related.has("potential"), "Clicking an input highlights its dependent path, not unrelated sibling inputs")
	view.canvas.focus_node("interest")
	var zoom := view._zoom
	view._set_zoom(zoom * 1.2, view._viewport.size / 2)
	_expect(view._zoom > zoom, "The large map can be zoomed for readable formulas")
	view.fit_map()
	var before := view.canvas.cards["growth"].tooltip_text as String
	view.close_map()
	var sim := controller.simulation
	sim.state.hand.append(&"starter_small_business")
	sim.state.budget = 100
	sim.state.political_capital = 20
	ui._dispatch(Command.play_card(&"starter_small_business"))
	await _settle(ui)
	_expect(view.canvas.cards["growth"].tooltip_text != before and view.canvas.cards["potential"].tooltip_text.contains("小企业扶持"), "Card play refreshes shared growth and its modifier sources")
	view.open_map()
	await _settle(ui)
	_expect(view.overlay.z_index > ui._played_table.z_index, "Game cards cannot draw over the graph modal")
	if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join("fincard-dependency-map.png"))
		view.canvas.focus_node("next_confidence")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join("fincard-dependency-map-focused.png"))
	var original_size := root.size
	root.size = Vector2i(1280, 800)
	await _settle(ui)
	_expect(root.get_visible_rect().encloses(view._viewport.get_global_rect()), "Map viewport fits smaller windows")
	view.close_map()
	_expect(root.get_visible_rect().encloses(ui._end_turn_button.get_global_rect()), "Closing the map restores accessible turn controls")
	root.size = original_size
	sim._fire_event(&"arcadia_ev_inequality")
	ui._render()
	_expect(view.open_button.disabled and view.canvas.graph["nodes"].is_empty() and not view.overlay.visible, "Unresolved choices cannot show a stale diagram")
	ui._dispatch(Command.resolve_event(1))
	await _settle(ui)
	_expect(not view.open_button.disabled and not view.canvas.graph["nodes"].is_empty(), "Resolving the event restores the live diagram")
	ui.free()
	await process_frame


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_arithmetic()
	_test_later_stages()
	await _test_ui()
	controller.free()
	await create_timer(0.35).timeout
	print("CALCULATION GRAPH TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
