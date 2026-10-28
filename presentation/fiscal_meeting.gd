class_name FiscalMeeting
extends Control

signal exit_requested

var content: VBoxContainer
var _title: Label
var _country: Label
var _budget: Label
var _income: Label


func _init() -> void:
	name = "FiscalMeeting"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := TextureRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.texture = UiTheme.gradient_background()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 36)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 20)
	margin.add_child(page)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	page.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_country = _label("", 15, UiTheme.MUTED)
	heading.add_child(_country)
	_title = _label("", 30, UiTheme.TEXT)
	heading.add_child(_title)
	var back := Button.new()
	back.text = "返回菜单"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: exit_requested.emit())
	header.add_child(back)
	var resources := HBoxContainer.new()
	resources.add_theme_constant_override("separation", 28)
	page.add_child(resources)
	_budget = _label("", 16, UiTheme.ACCENT_DARK)
	_income = _label("", 16, UiTheme.ACCENT_DARK)
	resources.add_child(_budget)
	resources.add_child(_income)
	page.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_top", 16)
	padding.add_theme_constant_override("margin_bottom", 16)
	center.add_child(padding)
	content = VBoxContainer.new()
	content.name = "Rewards"
	content.custom_minimum_size.x = 720
	content.add_theme_constant_override("separation", 16)
	padding.add_child(content)


func update_context(controller: GameController) -> void:
	var state := controller.simulation.state
	var year := state.year if state.flags.get("opening_setup", false) else state.year + 1
	var scenario: ScenarioDef = controller.scenarios.get(state.scenario_id)
	_country.text = scenario.display_name if scenario != null else "Fincard"
	_title.text = "第 %d 财年 · 财年会议" % year
	_budget.text = "预算余额 %d" % state.budget
	_income.text = "年度收入 %d" % controller.simulation.annual_income()


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
