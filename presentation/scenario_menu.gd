class_name ScenarioMenu
extends Control

signal country_selected(scenario_id: StringName)

var controller: GameController
var _list: GridContainer


func setup(p_controller: GameController) -> void:
	controller = p_controller
	_build()
	resized.connect(_update_columns)
	_update_columns()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 40)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)
	root.add_child(_label("FINCARD  /  国家经济档案", 16, UiTheme.ACCENT_DARK))
	root.add_child(_label("选择国家", 34, UiTheme.TEXT))
	root.add_child(HSeparator.new())
	var chapter := HBoxContainer.new()
	chapter.add_theme_constant_override("separation", 16)
	chapter.add_child(_label("国家档案", 18, UiTheme.ACCENT_DARK))
	root.add_child(chapter)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = GridContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 24)
	_list.add_theme_constant_override("v_separation", 24)
	scroll.add_child(_list)
	var scenarios := controller.available_scenarios()
	scenarios.sort_custom(func(a: ScenarioDef, b: ScenarioDef) -> bool:
		return a.goal.deadline_years < b.goal.deadline_years
	)
	for scenario: ScenarioDef in scenarios:
		_list.add_child(_country_card(scenario))
	if scenarios.is_empty():
		_list.add_child(_label("暂无可用国家", 18, UiTheme.MUTED))


func _country_card(scenario: ScenarioDef) -> Button:
	var button := Button.new()
	button.theme_type_variation = "CountryButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 480)
	button.tooltip_text = "查看 %s 的国家简介" % scenario.display_name
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	button.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	content.add_child(CountryFlag.create(scenario.id, 150))
	var badge := "入门  /  稳步发展" if scenario.goal.after_turn <= 12 else "危机  /  逆境复苏"
	content.add_child(_label(badge, 14, UiTheme.ACCENT_DARK))
	var title := _label(scenario.display_name, 25, UiTheme.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title)
	var goal := _label(scenario.goal.description, 15, UiTheme.MUTED)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.custom_minimum_size.x = 220
	goal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(goal)
	content.add_child(_label("%d 年任期    ·    %d 张初始牌    ·    查看国家档案 →" % [scenario.goal.deadline_years, scenario.starting_deck.size()], 15, UiTheme.ACCENT_DARK))
	_ignore_mouse(margin)
	button.pressed.connect(func() -> void: country_selected.emit(scenario.id))
	return button


func _update_columns() -> void:
	if _list != null:
		_list.columns = 1 if size.x < 1050 else 2


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
