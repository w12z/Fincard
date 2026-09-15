class_name ScenarioMenu
extends Control

signal start_requested(scenario_id: StringName)

var controller: GameController
var _list: VBoxContainer


func setup(p_controller: GameController) -> void:
	controller = p_controller
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Fincard — 选择开局情形"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "每个国家有独立的初始牌组、经济状态、事件池与最终经济目标。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	vbox.add_child(hint)

	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	vbox.add_child(_list)
	_populate()


func _populate() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var scenarios := controller.available_scenarios()
	if scenarios.is_empty():
		var empty := Label.new()
		empty.text = "未找到开局数据。请在 data/scenarios/ 下添加国家 JSON，并补齐 data/cards、data/events、data/cabinets、data/aids 与 data/config/rules.json。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(560, 0)
		_list.add_child(empty)
		return
	for scenario in scenarios:
		var button := Button.new()
		button.text = "%s\n%s" % [scenario.display_name, scenario.description]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(560, 64)
		button.theme_type_variation = "CardButton"
		var id: StringName = scenario.id
		button.pressed.connect(func() -> void: start_requested.emit(id))
		_list.add_child(button)
