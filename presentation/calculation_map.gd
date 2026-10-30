class_name CalculationMap
extends VBoxContainer

var open_button: Button
var overlay: Control
var canvas: DependencyCanvas
var _viewport: Control
var _stage: Control
var _message: Label
var _zoom_label: Label
var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _has_data := false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button = Button.new()
	open_button.text = "经济依赖关系图  ↗"
	open_button.custom_minimum_size.y = 46
	open_button.tooltip_text = "打开大型节点关系图，查看每项数据的影响路径。"
	open_button.pressed.connect(open_map)
	add_child(open_button)


func attach(host: Control) -> void:
	overlay = Control.new()
	overlay.name = "EconomyDependencyOverlay"
	overlay.z_index = 1000
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(overlay)
	overlay.hide()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.10, 0.18, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	overlay.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme._panel_style(Color("f4f7fc"), Color("b6cbe3"), 14, 2, 16))
	margin.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var toolbar := HBoxContainer.new()
	content.add_child(toolbar)
	var title := Label.new()
	title.text = "经济依赖关系图"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	_button(toolbar, "−", func() -> void: _set_zoom(_zoom / 1.2, _viewport.size / 2))
	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size.x = 60
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(_zoom_label)
	_button(toolbar, "+", func() -> void: _set_zoom(_zoom * 1.2, _viewport.size / 2))
	_button(toolbar, "全图", fit_map)
	_button(toolbar, "关闭  Esc", close_map)
	_message = Label.new()
	_message.text = "箭头表示依赖方向 · 点选节点聚焦关联路径 · 滚轮缩放 · 拖动空白平移"
	_message.add_theme_color_override("font_color", UiTheme.MUTED)
	content.add_child(_message)
	_viewport = Control.new()
	_viewport.name = "DependencyViewport"
	_viewport.clip_contents = true
	_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport.gui_input.connect(_navigate)
	_viewport.resized.connect(func() -> void:
		if overlay.visible:
			fit_map()
	)
	content.add_child(_viewport)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_stage)
	canvas = DependencyCanvas.new()
	_stage.add_child(canvas)
	canvas.node_focused.connect(func(title_text: String) -> void:
		_message.text = "关联路径：" + title_text + "  ·  再次点击取消聚焦" if title_text != "" else "箭头表示依赖方向 · 点选节点聚焦关联路径 · 滚轮缩放 · 拖动空白平移"
	)


func render(sim: Simulation, next: GameState) -> void:
	_has_data = next != null
	open_button.disabled = not _has_data
	open_button.text = "经济依赖关系图  ↗" if _has_data else "依赖图：待完成当前选择"
	canvas.render(EconomyDependencyGraph.build(sim, next))
	if not _has_data:
		close_map()


func open_map() -> void:
	if not _has_data:
		return
	overlay.get_parent().move_child(overlay, -1)
	overlay.show()
	fit_map.call_deferred()


func close_map() -> void:
	overlay.hide()
	_dragging = false


func fit_map() -> void:
	_zoom = minf(_viewport.size.x / EconomyDependencyGraph.SIZE.x, _viewport.size.y / EconomyDependencyGraph.SIZE.y)
	_pan = (_viewport.size - EconomyDependencyGraph.SIZE * _zoom) / 2
	_transform()


func _set_zoom(value: float, origin: Vector2) -> void:
	var next := clampf(value, 0.35, 2.0)
	_pan = origin - (origin - _pan) * next / _zoom
	_zoom = next
	_transform()


func _transform() -> void:
	_stage.position = _pan
	_stage.scale = Vector2.ONE * _zoom
	_zoom_label.text = "%d%%" % roundi(_zoom * 100)


func _navigate(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_set_zoom(_zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan += event.relative
		_transform()
		accept_event()


func _input(event: InputEvent) -> void:
	if is_instance_valid(overlay) and overlay.visible and event.is_action_pressed("ui_cancel"):
		close_map()
		get_viewport().set_input_as_handled()


func _button(parent: Control, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(44, 40)
	button.pressed.connect(action)
	parent.add_child(button)
