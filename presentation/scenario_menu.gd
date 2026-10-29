class_name ScenarioMenu
extends Control

signal country_selected(scenario_id: StringName)

var controller: GameController
var _country_buttons: Dictionary = {}
var _primary_button: Button
var _tutorial_button: Button
var _primary_flag: AspectRatioContainer
var _primary_goal: RichTextLabel


func setup(p_controller: GameController) -> void:
	controller = p_controller
	_build()
	resized.connect(_update_layout)
	_update_layout()


func _build() -> void:
	var heading := VBoxContainer.new()
	heading.position = Vector2(40, 32)
	heading.add_theme_constant_override("separation", 6)
	add_child(heading)
	heading.add_child(_label("FINCARD", 34, UiTheme.ACCENT_DARK))
	heading.add_child(_label("国家经济档案", 16, UiTheme.MUTED))
	var primary: ScenarioDef = controller.scenarios.get(&"arcadia")
	if primary != null:
		_primary_button = _country_card(primary)
		add_child(_primary_button)
		_country_buttons[primary.id] = _primary_button
	var tutorial: ScenarioDef = controller.scenarios.get(&"example_country")
	if tutorial != null:
		_tutorial_button = _tutorial_card(tutorial)
		add_child(_tutorial_button)
		_country_buttons[tutorial.id] = _tutorial_button


func _country_card(scenario: ScenarioDef) -> Button:
	var button := Button.new()
	button.theme_type_variation = "CountryButton"
	button.name = "ArcadiaEntry"
	button.set_meta("scenario_id", scenario.id)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = UiTheme.build().get_stylebox(state, "CountryButton").duplicate()
		style.border_color = UiTheme.ACCENT if state != "normal" else UiTheme.CARD_BORDER
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	button.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	_primary_flag = CountryFlag.create(scenario.id, 140)
	content.add_child(_primary_flag)
	var badge := _label("危机  /  逆境复苏", 14, UiTheme.ACCENT_DARK)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(badge)
	var title := _label(scenario.display_name, 28, UiTheme.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title)
	_primary_goal = ImpactText.create(scenario.goal.description, UiTheme.MUTED, 16)
	_primary_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_primary_goal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_primary_goal)
	var details := _label("%d 年任期    ·    %d 张初始牌" % [scenario.goal.deadline_years, scenario.starting_deck.size()], 15, UiTheme.MUTED)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(details)
	var enter := _label("查看国家档案  →", 18, UiTheme.ACCENT_DARK)
	enter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(enter)
	_ignore_mouse(margin)
	button.pressed.connect(func() -> void: country_selected.emit(scenario.id))
	return button


func _tutorial_card(scenario: ScenarioDef) -> Button:
	var button := Button.new()
	button.name = "TutorialEntry"
	button.set_meta("scenario_id", scenario.id)
	button.theme_type_variation = "CountryButton"
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	var flag := CountryFlag.create(scenario.id, 64)
	flag.custom_minimum_size.x = 90
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(flag)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	content.add_child(_label("新手体验关卡", 16, UiTheme.ACCENT_DARK))
	content.add_child(_label(scenario.display_name.split(" · ")[0], 22, UiTheme.TEXT))
	content.add_child(_label("查看档案  →", 14, UiTheme.MUTED))
	_ignore_mouse(margin)
	button.pressed.connect(func() -> void: country_selected.emit(scenario.id))
	return button


func _update_layout() -> void:
	var edge := 40.0 if size.x >= 1050 else 24.0
	if _tutorial_button != null:
		_tutorial_button.size = Vector2(minf(360, size.x - edge * 2), 140)
		_tutorial_button.position = size - _tutorial_button.size - Vector2(edge, edge)
	if _primary_button != null:
		_primary_button.size = Vector2(minf(620, size.x - edge * 2), clampf(size.y - 340, 240, 480))
		_primary_button.position = (size - _primary_button.size) / 2
		if _tutorial_button != null and _primary_button.get_rect().intersects(_tutorial_button.get_rect().grow(24)):
			_primary_button.position.y = _tutorial_button.position.y - 24 - _primary_button.size.y
		_primary_flag.custom_minimum_size.y = clampf(size.y - 640, 48, 140)
		_primary_goal.visible = size.y >= 760


func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_ignore_mouse(child)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
