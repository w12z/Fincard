class_name CountryProfile
extends Control

signal start_requested(scenario_id: StringName)
signal back_requested

const ROUTINE_REWARD_EVENTS: Array[StringName] = [
	&"arcadia_ev_recovery_institutions",
	&"arcadia_ev_recovery_support",
	&"arcadia_ev_recovery_mobilization",
]

var controller: GameController
var scenario: ScenarioDef
var _confirm_button: Button
var _back_button: Button
var _columns: BoxContainer
var _confirmed: bool = false


func setup(p_controller: GameController, scenario_id: StringName) -> void:
	controller = p_controller
	scenario = controller.scenarios.get(scenario_id)
	if scenario == null:
		back_requested.emit()
		return
	_build()
	resized.connect(_update_columns)
	_update_columns()
	_back_button.grab_focus()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 40)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)
	root.add_child(_text("FINCARD  /  国家档案", 16, UiTheme.ACCENT_DARK))
	root.add_child(_text(scenario.display_name, 34, UiTheme.TEXT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_columns = BoxContainer.new()
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 24)
	scroll.add_child(_columns)
	var left := _panel(_columns)
	left.get_parent().custom_minimum_size.x = 340
	left.add_child(CountryFlag.create(scenario.id, 190))
	left.add_child(_text("初始经济", 20, UiTheme.ACCENT_DARK))
	for id in [&"gdp", &"inflation", &"unemployment", &"confidence", &"interest_rate"]:
		var row := HBoxContainer.new()
		var name_label := _text(TextFormatter.indicator(controller.labels, id), 16, UiTheme.MUTED)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var suffix := "%" if id in [&"inflation", &"unemployment", &"interest_rate"] else ""
		var value_label := _text(TextFormatter.fmt(float(scenario.indicators.get(id, 0))) + suffix, 18, UiTheme.TEXT)
		value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(value_label)
		left.add_child(row)
	left.add_child(HSeparator.new())
	left.add_child(ImpactText.create("每财年收入 %d 预算 · 余额保留 %d%%" % [scenario.annual_income, roundi(float(controller.rules.get("budget_retention", 0.5)) * 100)], UiTheme.ACCENT_DARK, 16))
	left.add_child(ImpactText.create("%d 张初始牌  ·  %d 年任期" % [scenario.starting_deck.size(), scenario.goal.deadline_years], UiTheme.ACCENT_DARK, 16))
	var right := _panel(_columns)
	right.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section(right, "国家背景", scenario.description)
	right.add_child(_text("任期目标", 20, UiTheme.TEXT))
	for condition in scenario.goal.conditions:
		right.add_child(ImpactText.create("◇  " + TextFormatter.condition_text(controller.labels, condition), UiTheme.POSITIVE, 17))
	if scenario.goal.after_turn > 0:
		right.add_child(ImpactText.create("胜利判定：第 %d 回合起" % (scenario.goal.after_turn + 1), UiTheme.WARNING, 15))
	right.add_child(HSeparator.new())
	right.add_child(_text("风险与失败条件", 20, UiTheme.TEXT))
	for condition in scenario.goal.loss_conditions:
		right.add_child(ImpactText.create("·  " + TextFormatter.condition_text(controller.labels, condition), UiTheme.NEGATIVE, 15))
	right.add_child(_text("任期届满未达成目标则失败。", 14, UiTheme.MUTED))
	if not scenario.scheduled_events.is_empty():
		right.add_child(HSeparator.new())
		right.add_child(_text("重大事件", 20, UiTheme.TEXT))
		var turn_numbers := scenario.scheduled_events.keys()
		turn_numbers.sort()
		for turn_number in turn_numbers:
			if scenario.scheduled_events[turn_number] in ROUTINE_REWARD_EVENTS:
				continue
			var event: EconomyEventDef = controller.events.get(scenario.scheduled_events[turn_number])
			if event != null:
				var phase := "结束" if scenario.scheduled_event_phases.get(turn_number, &"turn_start") == &"turn_end" else "开始"
				right.add_child(ImpactText.create("第 %d 回合%s  /  %s" % [turn_number, phase, event.title], UiTheme.WARNING, 16))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	root.add_child(actions)
	_back_button = Button.new()
	_back_button.text = "← 返回主界面"
	_back_button.tooltip_text = "Esc"
	_back_button.custom_minimum_size = Vector2(190, 48)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	actions.add_child(_back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_confirm_button = Button.new()
	_confirm_button.text = "确认进入  →"
	_confirm_button.theme_type_variation = "PrimaryButton"
	_confirm_button.custom_minimum_size = Vector2(230, 48)
	_confirm_button.pressed.connect(_confirm)
	actions.add_child(_confirm_button)


func _confirm() -> void:
	if _confirmed:
		return
	_confirmed = true
	_confirm_button.disabled = true
	start_requested.emit(scenario.id)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _confirmed:
		get_viewport().set_input_as_handled()
		back_requested.emit()


func _update_columns() -> void:
	if _columns != null:
		_columns.vertical = size.x < 1050


func _panel(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "CountryPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	return content


func _section(parent: Control, title: String, body: String) -> void:
	parent.add_child(_text(title, 20, UiTheme.TEXT))
	parent.add_child(_text(body, 17, UiTheme.MUTED))


func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
