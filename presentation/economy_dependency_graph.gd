class_name EconomyDependencyGraph
extends RefCounted

const SIZE := Vector2(1760, 1200)


static func build(sim: Simulation, next: GameState) -> Dictionary:
	var graph := {"nodes": [], "edges": []}
	if next == null:
		return graph
	var branches := EconomyCalculation.branches(sim, next)
	var model := sim.economy
	var state := sim.state
	var inputs := [
		["potential", "潜在增长", model.coefficient(state, &"gdp_auto"), "%"],
		["confidence", "当前信心", model.value(state, &"confidence"), ""],
		["interest", "当前利率", model.value(state, &"interest_rate"), "%"],
		["inflation", "当前通胀", model.value(state, &"inflation"), "%"],
		["unemployment", "当前失业率", model.value(state, &"unemployment"), "%"],
		["gdp", "当前 GDP", model.value(state, &"gdp"), ""],
	]
	for index in inputs.size():
		var input: Array = inputs[index]
		_add(graph, input[0], input[1], TextFormatter.fmt(input[2]) + input[3], "结算前的有效值", Rect2(40 + index * 282, 60, 240, 128), "input")
	var potential := _branch(_branch(branches, "growth_now")["children"], "gdp_auto")
	var sources := PackedStringArray()
	for source: Dictionary in potential["children"]:
		sources.append("%s %s" % [source["title"], TextFormatter.signed(source["value"])])
	graph["nodes"][0]["body"] = "含国家精神／改革／投资"
	graph["nodes"][0]["tooltip"] = "\n".join(sources)
	var growth := _branch(branches, "growth_now")
	_add(graph, "growth", "本轮实际增长率", TextFormatter.fmt(growth["value"]) + "%", "潜在增长 + 信心÷100\n− 利率÷10 − 物价拖累", Rect2(740, 330, 310, 155), "hub")
	var target := model.coefficient(state, &"inflation_target")
	_add(graph, "target", "通胀目标", TextFormatter.fmt(target) + "%", "温和区间 %s%%～%s%%" % [TextFormatter.fmt(target - 2), TextFormatter.fmt(target + 2)], Rect2(40, 280, 240, 128), "rule")
	_add(graph, "natural", "自然失业率", TextFormatter.fmt(model.coefficient(state, &"natural_unemployment")) + "%", "就业回归／高失业基准", Rect2(40, 420, 240, 128), "rule")
	var drag := EconomyBuilder.inflation_growth_drag(state, model)
	_add(graph, "drag", "物价拖累", TextFormatter.fmt(-drag), "高于区间：差额×0.15\n低于区间：差额×0.20", Rect2(410, 330, 250, 155), "driver")
	_edge(graph, "inflation", "drag", "偏离温和区间")
	_edge(graph, "target", "drag", "区间基准", false, "right", "left")
	_edge(graph, "potential", "growth", TextFormatter.signed(model.coefficient(state, &"gdp_auto")), true)
	_edge(graph, "confidence", "growth", "÷100  " + TextFormatter.signed(model.value(state, &"confidence") / 100.0), true)
	_edge(graph, "interest", "growth", "−÷10  " + TextFormatter.signed(-model.value(state, &"interest_rate") / 10.0), true)
	_edge(graph, "drag", "growth", TextFormatter.fmt(-drag), true, "right", "left")
	var special := PackedStringArray()
	var confidence_terms: Array = _branch(_branch(branches, "confidence")["children"], "equation")["children"]
	var special_total := 0.0
	for term: Dictionary in confidence_terms:
		if String(term["key"]).begins_with("special_"):
			special.append("%s %s" % [term["title"], TextFormatter.signed(term["value"])])
			special_total += float(term["value"])
	_add(graph, "special", "市场情绪修正", TextFormatter.signed(special_total), "\n".join(special) if not special.is_empty() else "无股市狂热／信心崩盘修正", Rect2(1390, 300, 330, 155), "driver")
	_edge(graph, "growth", "special", "按增长率触发", false, "right", "left")
	for index in 4:
		var id: StringName = [&"gdp", &"inflation", &"unemployment", &"confidence"][index]
		var branch := _branch(branches, String(id))
		var economic := _branch(branch["children"], "equation")
		var rows := PackedStringArray()
		for term: Dictionary in economic["children"]:
			rows.append("%s %s" % [term["title"], TextFormatter.signed(term["value"])])
		var later := float(branch["value"]) - float(economic["value"])
		var body := "经济公式 %s\n边界／后续触发 %s" % [TextFormatter.signed(economic["value"]), TextFormatter.signed(later)]
		var key := "next_" + String(id)
		_add(graph, key, "%s → 下回合" % branch["title"], "%s → %s" % [TextFormatter.fmt(branch["current"]), TextFormatter.fmt(branch["future"])], body, Rect2(40 + index * 440, 740, 360, 226), "output")
		var node: Dictionary = graph["nodes"].back()
		node["delta"] = TextFormatter.signed(branch["value"])
		node["color"] = EconomyForecast.change_color(sim, id, branch["current"], branch["future"])
		node["tooltip"] = "\n".join(rows) + "\n" + branch["tooltip"]
		var growth_term := _branch(economic["children"], "growth")
		_edge(graph, "growth", key, "增长贡献 " + TextFormatter.signed(growth_term["value"]), true)
		_edge(graph, String(id), key, "结算基数" if id == &"gdp" else "当前值参与计算")
	_edge(graph, "target", "next_inflation", "目标回归", false, "right", "top")
	_edge(graph, "natural", "next_unemployment", "自然水平回归", false, "right", "top")
	_edge(graph, "inflation", "next_confidence", "物价偏离惩罚")
	_edge(graph, "target", "next_confidence", "物价惩罚基准", false, "right", "top")
	_edge(graph, "unemployment", "next_confidence", "高失业惩罚")
	_edge(graph, "natural", "next_confidence", "高失业基准", false, "right", "top")
	_edge(graph, "special", "next_confidence", "市场情绪 " + TextFormatter.signed(special_total), true)
	for entry in [[&"infl_anchor", "额外通胀回归", "next_inflation", 410], [&"u_revert", "额外就业回归", "next_unemployment", 830]]:
		var coefficient := model.coefficient(state, entry[0])
		if not is_zero_approx(coefficient):
			_add(graph, String(entry[0]), entry[1], TextFormatter.fmt(coefficient), "来自已生效的内阁／改革修正", Rect2(entry[3], 540, 270, 140), "rule")
			_edge(graph, String(entry[0]), entry[2], "额外回归系数")
	if not is_zero_approx(model.coefficient(state, &"infl_anchor")) or not is_zero_approx(model.coefficient(state, &"u_revert")):
		# Leave a clear corridor around acquired coefficient nodes instead of
		# letting a growth connection disappear behind an unrelated card.
		for edge: Dictionary in graph["edges"]:
			if edge["from"] != "growth" or not String(edge["to"]).begins_with("next_"):
				continue
			var index := ["next_gdp", "next_inflation", "next_unemployment", "next_confidence"].find(edge["to"])
			var rail := 710.0 if index < 2 else 1120.0
			var x := 220.0 + 440.0 * index
			edge["via"] = PackedVector2Array([Vector2(895, 510), Vector2(rail, 510), Vector2(rail, 705), Vector2(x, 705)])
			edge["label_on_focus"] = true
	if next.turn > state.turn:
		var rate := float(model.derived[&"growth"].call(next, model))
		var formula := "下轮潜在增长 %s · 利率 %s\n更新后的信心与物价重新参与计算" % [TextFormatter.fmt(model.coefficient(next, &"gdp_auto")), TextFormatter.fmt(model.value(next, &"interest_rate"))]
		_add(graph, "growth_next", "下一轮增长率（反馈）", TextFormatter.fmt(rate) + "%", formula, Rect2(620, 1000, 520, 144), "hub")
		_edge(graph, "next_confidence", "growth_next", "下一轮信心÷100")
		_edge(graph, "next_inflation", "growth_next", "下一轮物价拖累")
	return graph


static func _branch(nodes: Array, key: String) -> Dictionary:
	for node: Dictionary in nodes:
		if node["key"] == key:
			return node
	return {}


static func _add(graph: Dictionary, id: String, title: String, value: String, body: String, rect: Rect2, kind: String) -> void:
	graph["nodes"].append({"id": id, "title": title, "value": value, "body": body, "rect": rect, "kind": kind, "tooltip": ""})


static func _edge(graph: Dictionary, from: String, to: String, label: String, primary: bool = false, from_port: String = "bottom", to_port: String = "top") -> void:
	graph["edges"].append({"from": from, "to": to, "label": label, "primary": primary, "from_port": from_port, "to_port": to_port})
