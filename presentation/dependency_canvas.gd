class_name DependencyCanvas
extends Control

signal node_focused(title: String)

var graph := {"nodes": [], "edges": []}
var cards: Dictionary = {}
var selected := ""
var _related: Dictionary = {}


func _init() -> void:
	size = EconomyDependencyGraph.SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func render(data: Dictionary) -> void:
	graph = data
	for child in get_children():
		remove_child(child)
		child.queue_free()
	cards.clear()
	for node: Dictionary in graph["nodes"]:
		var button := Button.new()
		button.name = node["id"]
		button.position = node["rect"].position
		button.size = node["rect"].size
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		var color := _color(node["kind"])
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, UiTheme._panel_style(Color.WHITE.lerp(color, 0.07 if state == "normal" else 0.16), color, 12, 3 if node["kind"] == "hub" else 2, 12))
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 14)
		button.add_child(margin)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 6)
		margin.add_child(content)
		var title := Label.new()
		title.text = node["title"]
		title.add_theme_font_size_override("font_size", 19)
		title.add_theme_color_override("font_color", color)
		content.add_child(title)
		var value := Label.new()
		value.text = node["value"]
		value.add_theme_font_override("font", ImpactText.NUMBER_FONT)
		value.add_theme_font_size_override("font_size", 23 if node["kind"] == "output" else 26)
		value.add_theme_color_override("font_color", ImpactText.GOLD)
		content.add_child(value)
		if node.has("delta"):
			var delta := Label.new()
			delta.text = "净变化  " + node["delta"]
			delta.add_theme_font_size_override("font_size", 19)
			delta.add_theme_color_override("font_color", node["color"])
			content.add_child(delta)
		var body := ImpactText.create(node["body"], UiTheme.MUTED, 16)
		content.add_child(body)
		_ignore_mouse(margin)
		button.tooltip_text = node["title"] + "\n" + node["value"] + "\n" + node["body"] + "\n" + node["tooltip"]
		button.pressed.connect(focus_node.bind(String(node["id"])))
		add_child(button)
		cards[node["id"]] = button
	if not cards.has(selected):
		selected = ""
	_update_focus()


func focus_node(id: String) -> void:
	selected = "" if selected == id else id
	_update_focus()
	for node: Dictionary in graph["nodes"]:
		if node["id"] == selected:
			node_focused.emit(node["title"])
			return
	node_focused.emit("")


func _update_focus() -> void:
	_related.clear()
	if selected != "":
		_related[selected] = true
		# Ancestors and descendants are walked separately: selecting an input
		# must not accidentally include siblings merely sharing an output.
		for upstream in [true, false]:
			var visited := {selected: true}
			var queue: Array[String] = [selected]
			while not queue.is_empty():
				var id: String = queue.pop_back()
				for edge: Dictionary in graph["edges"]:
					if edge["to" if upstream else "from"] != id:
						continue
					var other := String(edge["from" if upstream else "to"])
					if not visited.has(other):
						visited[other] = true
						_related[other] = true
						queue.append(other)
	for id: String in cards:
		cards[id].modulate.a = 1.0 if selected == "" or _related.has(id) else 0.22
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(40, 30), "01  当期数据与既有修正", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.MUTED)
	draw_string(font, Vector2(40, 720), "03  完整预测结果（经济结算 + 边界／内阁／到期／自动出牌）", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiTheme.MUTED)
	draw_string(font, Vector2(410, 290), "02  依赖运算", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiTheme.MUTED)
	draw_string(font, Vector2(40, 1180), "同一轮的公式均使用上方当期数据；下方预测值不会在本轮反向代入。预测不含未来事件及新增奖励。", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.MUTED)
	for edge: Dictionary in graph["edges"]:
		if not cards.has(edge["from"]) or not cards.has(edge["to"]):
			continue
		var active := selected == "" or (_related.has(edge["from"]) and _related.has(edge["to"]))
		var highlighted := selected != "" and active
		var color := Color("7354b3") if edge["primary"] else Color("7892ae")
		color.a = 0.95 if highlighted else (0.8 if edge["primary"] else 0.4)
		if not active:
			color.a = 0.06
		var a := _port(cards[edge["from"]].get_rect(), edge["from_port"])
		var b := _port(cards[edge["to"]].get_rect(), edge["to_port"])
		var curve := Curve2D.new()
		var length := maxf(70, absf(b.y - a.y) * 0.45)
		curve.add_point(a, Vector2.ZERO, _direction(edge["from_port"]) * length)
		curve.add_point(b, _direction(edge["to_port"]) * length, Vector2.ZERO)
		var points := curve.get_baked_points()
		if edge.has("via"):
			points = PackedVector2Array([a])
			points.append_array(edge["via"])
			points.append(b)
		draw_polyline(points, color, 3.5 if highlighted else (2.5 if edge["primary"] else 1.5), true)
		var direction := (b - points[maxi(0, points.size() - 2)]).normalized()
		draw_colored_polygon(PackedVector2Array([b, b - direction.rotated(0.45) * 13, b - direction.rotated(-0.45) * 13]), color)
		if highlighted or (selected == "" and edge["primary"] and not edge.get("label_on_focus", false)):
			var point := curve.sample_baked(curve.get_baked_length() * 0.48)
			if edge.has("via"):
				point = points[1].lerp(points[2], 0.5)
			var label_size := font.get_string_size(edge["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			var rect := Rect2(point - label_size / 2 - Vector2(5, 5), label_size + Vector2(10, 10))
			draw_style_box(UiTheme._panel_style(Color("f4f7fc"), Color.TRANSPARENT, 4, 0, 0), rect)
			draw_string(font, rect.position + Vector2(5, label_size.y - 1), edge["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


static func _port(rect: Rect2, side: String) -> Vector2:
	match side:
		"right": return Vector2(rect.end.x, rect.get_center().y)
		"left": return Vector2(rect.position.x, rect.get_center().y)
		"top": return Vector2(rect.get_center().x, rect.position.y)
	return Vector2(rect.get_center().x, rect.end.y)


static func _direction(side: String) -> Vector2:
	return {"right": Vector2.RIGHT, "left": Vector2.LEFT, "top": Vector2.UP, "bottom": Vector2.DOWN}.get(side, Vector2.DOWN)


static func _color(kind: String) -> Color:
	return {"input": Color("356aaf"), "hub": Color("7850af"), "driver": Color("b07828"), "rule": Color("62758e"), "output": Color("16836b"), "resource": Color("527a8e")}.get(kind, UiTheme.TEXT)


static func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)
