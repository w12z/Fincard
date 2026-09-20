class_name GameUI
extends Control

signal exit_requested

const LOG_LIMIT := 1000
const TYPE_LABELS := {
	Reward.Type.CARD: "新卡牌",
	Reward.Type.CABINET: "任命内阁",
	Reward.Type.AID: "申请援助",
}

var controller: GameController
var _state: GameState

var _header: HBoxContainer
var _goal_box: VBoxContainer
var _indicators_box: VBoxContainer
var _modifiers_box: VBoxContainer
var _cabinets_box: VBoxContainer
var _aids_box: VBoxContainer
var _hand_box: HFlowContainer
var _deck_label: Label
var _end_turn_button: Button
var _log: RichTextLabel
var _overlay_root: CenterContainer
var _overlay_box: VBoxContainer

var _log_lines: Array[String] = []
var _reward_selection: Dictionary = {}
var _budget_selection: StringName = &""


func setup(p_controller: GameController, scenario_id: StringName) -> void:
	controller = p_controller
	_build()
	_play_events(controller.start_run(scenario_id))
	_render()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 16)
	root.add_child(_header)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(260, 0)
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left)
	_goal_box = _make_section(left, "最终目标")
	_indicators_box = _make_section(left, "经济指标")
	_modifiers_box = _make_section(left, "生效中的修正")
	_cabinets_box = _make_section(left, "内阁")
	_aids_box = _make_section(left, "外部援助")

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	var hand_section := _make_section(center, "手牌")
	hand_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hand_box = HFlowContainer.new()
	_hand_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hand_box.add_theme_constant_override("h_separation", 8)
	_hand_box.add_theme_constant_override("v_separation", 8)
	hand_section.add_child(_hand_box)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	center.add_child(footer)
	_deck_label = Label.new()
	_deck_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_deck_label)
	_end_turn_button = Button.new()
	_end_turn_button.text = "结束回合"
	_end_turn_button.custom_minimum_size = Vector2(140, 40)
	_end_turn_button.theme_type_variation = "PrimaryButton"
	_end_turn_button.pressed.connect(func() -> void: _dispatch(Command.end_turn()))
	footer.add_child(_end_turn_button)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(320, 0)
	split.add_child(right)
	var log_section := _make_section(right, "事件日志")
	log_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(300, 0)
	log_section.add_child(_log)

	_build_overlay()


func _build_overlay() -> void:
	_overlay_root = CenterContainer.new()
	_overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.visible = false
	add_child(_overlay_root)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	_overlay_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	_overlay_box = VBoxContainer.new()
	_overlay_box.custom_minimum_size = Vector2(460, 0)
	_overlay_box.add_theme_constant_override("separation", 8)
	margin.add_child(_overlay_box)


func _make_section(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
	box.add_child(label)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	box.add_child(content)
	return content


func _render() -> void:
	_state = controller.simulation.state
	_render_header()
	_render_goal()
	_render_indicators()
	_render_modifiers()
	_render_cabinets()
	_render_aids()
	_render_hand()
	_render_log()
	_render_overlay()


func _render_header() -> void:
	_clear(_header)
	var title := Label.new()
	title.text = "Fincard"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)
	_header.add_child(_label("第 %d 财年" % _state.year))
	_header.add_child(_label("回合 %d/%d" % [_state.turn_in_year, _turns_per_year()]))
	var budget_label := _label("财政预算 %d" % _state.budget)
	budget_label.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
	_header.add_child(budget_label)
	var political_label := _label("政治行动点 %d" % _state.political_capital)
	political_label.add_theme_color_override("font_color", UiTheme.POSITIVE)
	_header.add_child(political_label)
	var status_label := _label("状态：%s" % _status_text())
	status_label.add_theme_color_override("font_color", _status_color())
	_header.add_child(status_label)
	var back := Button.new()
	back.text = "返回菜单"
	back.pressed.connect(func() -> void: exit_requested.emit())
	_header.add_child(back)


func _render_goal() -> void:
	_clear(_goal_box)
	var scenario: ScenarioDef = controller.scenarios.get(_state.scenario_id)
	if scenario == null or scenario.goal == null:
		_goal_box.add_child(_label("（无）"))
		return
	var goal := scenario.goal
	if goal.description != "":
		_goal_box.add_child(_wrapped(goal.description, UiTheme.MUTED))
	for condition in goal.conditions:
		_goal_box.add_child(_wrapped("达成：%s" % TextFormatter.condition_text(_labels(), condition), UiTheme.POSITIVE))
	for condition in goal.loss_conditions:
		_goal_box.add_child(_wrapped("失败：%s" % TextFormatter.condition_text(_labels(), condition), UiTheme.NEGATIVE))
	if goal.deadline_years > 0:
		_goal_box.add_child(_colored("期限：第 %d 财年" % goal.deadline_years, UiTheme.WARNING))
	if goal.after_turn > 0:
		_goal_box.add_child(_colored("胜利判定：自第 %d 回合起" % (goal.after_turn + 1), UiTheme.WARNING))


func _render_indicators() -> void:
	_clear(_indicators_box)
	var ids := controller.simulation.economy.indicator_ids
	if ids.is_empty():
		_indicators_box.add_child(_label("（未定义指标）"))
	else:
		for id in ids:
			_indicators_box.add_child(_label("%s：%s" % [
				TextFormatter.indicator(_labels(), id),
				_fmt(controller.simulation.economy.value(_state, id)),
			]))
	var derived := controller.simulation.economy.derived_ids
	if not derived.is_empty():
		_indicators_box.add_child(_colored("—— 派生 ——", UiTheme.WARNING))
		for id in derived:
			_indicators_box.add_child(_label("%s：%s" % [
				TextFormatter.indicator(_labels(), id),
				_fmt(controller.simulation.economy.value(_state, id)),
			]))


func _render_modifiers() -> void:
	_clear(_modifiers_box)
	if _state.modifiers.is_empty():
		_modifiers_box.add_child(_label("（无）"))
		return
	for modifier in _state.modifiers:
		var remaining := "永久" if modifier.is_permanent() else "%d 回合" % modifier.remaining_turns
		var modifier_label := TextFormatter.indicator(_labels(), modifier.target)
		if modifier.scope == Modifier.SCOPE_COEFFICIENT:
			modifier_label = "系数·" + TextFormatter.coefficient(_labels(), modifier.target)
		_modifiers_box.add_child(_label("%s %s %s（%s）" % [
			modifier_label,
			_op_word(modifier.op),
			TextFormatter.fmt(modifier.value),
			remaining,
		]))


func _render_cabinets() -> void:
	_clear(_cabinets_box)
	if _state.cabinets.is_empty():
		_cabinets_box.add_child(_label("（无）"))
		return
	for cabinet in _state.cabinets:
		_cabinets_box.add_child(_colored(cabinet.display_name, UiTheme.ACCENT_DARK))
		if cabinet.description != "":
			_cabinets_box.add_child(_wrapped(cabinet.description, UiTheme.MUTED))
		for modifier in cabinet.modifiers:
			_cabinets_box.add_child(_wrapped("· " + TextFormatter.effect_text(_labels(), modifier), UiTheme.TEXT))
		for trigger in cabinet.triggers:
			_cabinets_box.add_child(_wrapped("· " + TextFormatter.trigger_text(_labels(), trigger), UiTheme.TEXT))


func _render_aids() -> void:
	_clear(_aids_box)
	if _state.aids.is_empty():
		_aids_box.add_child(_label("（无）"))
		return
	for entry in _state.aids:
		var definition: AidDef = entry["def"]
		_aids_box.add_child(_colored("%s ×%d" % [definition.display_name, int(entry["uses"])], UiTheme.ACCENT_DARK))
		if definition.description != "":
			_aids_box.add_child(_wrapped(definition.description, UiTheme.MUTED))
		if not definition.effects.is_empty():
			_aids_box.add_child(_wrapped("· " + TextFormatter.effects_text(_labels(), definition.effects), UiTheme.TEXT))
		var use := Button.new()
		use.text = "使用"
		use.disabled = _busy() or _state.run_status != GameState.RunStatus.RUNNING
		var aid_id: StringName = definition.id
		use.pressed.connect(func() -> void: _dispatch(Command.use_aid(aid_id)))
		_aids_box.add_child(use)


func _render_hand() -> void:
	_clear(_hand_box)
	if _state.hand.is_empty():
		_hand_box.add_child(_label("（无手牌）"))
		return
	for card_id in _state.hand:
		var card: CardDef = controller.cards.get(card_id)
		if card == null:
			continue
		var type_label := TextFormatter.card_type_name(_labels(), card.card_type)
		var type_color := UiTheme.card_type_color(card.card_type)
		var lines := PackedStringArray([
			"［%s］%s" % [type_label, card.display_name],
			"预算 %d · 政治 %d" % [card.cost, card.political_cost],
		])
		for effect in card.effects:
			lines.append("· " + TextFormatter.effect_text(_labels(), effect))
		var button := Button.new()
		button.text = "\n".join(lines)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_color_override("font_color", type_color)
		button.add_theme_color_override("font_hover_color", type_color)
		button.add_theme_color_override("font_pressed_color", type_color)
		button.add_theme_color_override("font_disabled_color", Color(type_color, 0.55))
		button.tooltip_text = "［%s］\n%s" % [type_label, _detail_text(card.description, card.effects, controller.simulation.groups_of("cards", card.id))]
		button.custom_minimum_size = Vector2(180, 0)
		button.theme_type_variation = "CardButton"
		button.disabled = _busy() or _state.run_status != GameState.RunStatus.RUNNING \
			or _state.budget < card.cost or _state.political_capital < card.political_cost
		button.pressed.connect(func() -> void: _dispatch(Command.play_card(card_id)))
		_hand_box.add_child(button)


func _render_log() -> void:
	_log.text = "\n".join(_log_lines)


func _render_overlay() -> void:
	_clear(_overlay_box)
	if _state.run_status != GameState.RunStatus.RUNNING:
		_show_result()
		return
	if _state.pending_event != &"":
		_show_event()
		return
	if not _state.pending_budget_plans.is_empty():
		_show_budget()
		return
	if not _state.pending_rewards.is_empty():
		_show_rewards()
		return
	_overlay_root.visible = false


func _show_event() -> void:
	var definition: EconomyEventDef = controller.events.get(_state.pending_event)
	var title := Label.new()
	title.text = definition.title if definition != null else String(_state.pending_event)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_overlay_box.add_child(title)
	if definition != null and definition.description != "":
		_overlay_box.add_child(_wrapped(definition.description, UiTheme.TEXT, 460.0))
	if _state.pending_event_choices.is_empty():
		if definition != null and not definition.effects.is_empty():
			_overlay_box.add_child(_colored("具体作用", UiTheme.ACCENT_DARK))
			_overlay_box.add_child(_wrapped(TextFormatter.effects_text(_labels(), definition.effects), UiTheme.TEXT, 460.0))
		var cont := Button.new()
		cont.text = "继续"
		cont.theme_type_variation = "PrimaryButton"
		cont.pressed.connect(func() -> void: _dispatch(Command.resolve_event(-1)))
		_overlay_box.add_child(cont)
	else:
		for index in range(_state.pending_event_choices.size()):
			var choice: Dictionary = _state.pending_event_choices[index]
			var button := Button.new()
			var text := str(choice.get("label", "..."))
			if definition != null and index < definition.choices.size() and not definition.choices[index].effects.is_empty():
				text += "\n" + TextFormatter.effects_text(_labels(), definition.choices[index].effects)
			button.text = text
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.tooltip_text = choice.get("description", "")
			var choice_index := index
			button.pressed.connect(func() -> void: _dispatch(Command.resolve_event(choice_index)))
			_overlay_box.add_child(button)
	_overlay_root.visible = true


func _show_budget() -> void:
	var title := Label.new()
	title.text = "确定下一年度预算"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_overlay_box.add_child(title)
	var hint := _label("预算与政治行动点将在下个财年全程作为出牌消耗。")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	hint.custom_minimum_size = Vector2(460, 0)
	_overlay_box.add_child(hint)
	_budget_selection = _state.pending_budget_plans[0]
	var button_group := ButtonGroup.new()
	for index in range(_state.pending_budget_plans.size()):
		var plan_id: StringName = _state.pending_budget_plans[index]
		var plan: BudgetPlanDef = controller.budgets.get(plan_id)
		var check := CheckBox.new()
		if plan != null:
			check.text = "%s　预算 %d · 政治 %d" % [plan.display_name, plan.budget, plan.political_capital]
			check.tooltip_text = _detail_text(plan.description, plan.effects, controller.simulation.groups_of("budgets", plan.id))
		else:
			check.text = String(plan_id)
		check.button_group = button_group
		check.button_pressed = index == 0
		var chosen := plan_id
		check.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_budget_selection = chosen
		)
		_overlay_box.add_child(check)
	var confirm := Button.new()
	confirm.text = "确认预算"
	confirm.custom_minimum_size = Vector2(0, 36)
	confirm.theme_type_variation = "PrimaryButton"
	confirm.pressed.connect(_confirm_budget)
	_overlay_box.add_child(confirm)
	_overlay_root.visible = true


func _show_rewards() -> void:
	_reward_selection.clear()
	var title := Label.new()
	title.text = "财年总结 · 奖励"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_overlay_box.add_child(title)
	for group_index in range(_state.pending_rewards.size()):
		var group: Dictionary = _state.pending_rewards[group_index]
		var group_title := _label(str(TYPE_LABELS.get(group.get("type"), "奖励")))
		_overlay_box.add_child(group_title)
		var options: Array = group.get("options", [])
		var button_group := ButtonGroup.new()
		for option_index in range(options.size()):
			var reward: Reward = options[option_index]
			var check := CheckBox.new()
			check.text = reward.label
			check.tooltip_text = _reward_detail(reward)
			if reward.type == Reward.Type.CARD:
				var reward_card: CardDef = controller.cards.get(reward.id)
				if reward_card != null:
					var reward_color := UiTheme.card_type_color(reward_card.card_type)
					check.add_theme_color_override("font_color", reward_color)
					check.add_theme_color_override("font_hover_color", reward_color)
					check.add_theme_color_override("font_pressed_color", reward_color)
			check.button_group = button_group
			var gi := group_index
			var oi := option_index
			check.toggled.connect(func(pressed: bool) -> void:
				if pressed:
					_reward_selection[gi] = oi
			)
			_overlay_box.add_child(check)
		var skip := CheckBox.new()
		skip.text = "跳过"
		skip.button_group = button_group
		var gi2 := group_index
		skip.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_reward_selection.erase(gi2)
		)
		_overlay_box.add_child(skip)
	var confirm := Button.new()
	confirm.text = "确认"
	confirm.custom_minimum_size = Vector2(0, 36)
	confirm.theme_type_variation = "PrimaryButton"
	confirm.pressed.connect(_confirm_rewards)
	_overlay_box.add_child(confirm)
	_overlay_root.visible = true


func _show_result() -> void:
	var won := _state.run_status == GameState.RunStatus.WON
	var title := Label.new()
	title.text = "目标达成！" if won else "计划失败"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.POSITIVE if won else UiTheme.NEGATIVE)
	_overlay_box.add_child(title)
	var info := _label("第 %d 财年结束 · %s" % [_state.year, _indicator_summary()])
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(460, 0)
	_overlay_box.add_child(info)
	var back := Button.new()
	back.text = "返回菜单"
	back.custom_minimum_size = Vector2(0, 36)
	back.theme_type_variation = "PrimaryButton"
	back.pressed.connect(func() -> void: exit_requested.emit())
	_overlay_box.add_child(back)
	_overlay_root.visible = true


func _confirm_budget() -> void:
	if _budget_selection == &"":
		return
	_dispatch(Command.choose_budget(_budget_selection))


func _confirm_rewards() -> void:
	var picks: Array = []
	for group_index in range(_state.pending_rewards.size()):
		picks.append(_reward_selection.get(group_index, -1))
	_dispatch(Command.choose_reward(picks))


func _dispatch(command: Command) -> void:
	_play_events(controller.dispatch(command))
	_render()


func _play_events(events: Array) -> void:
	for event in events:
		var line := _describe(event)
		if line != "":
			_log_lines.append(line)
	if _log_lines.size() > LOG_LIMIT:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_LIMIT)


func _describe(event: Event) -> String:
	var params := event.params
	match event.kind:
		Event.Kind.RUN_STARTED:
			return "[b]开局：%s[/b]" % _scenario_name(params.get("scenario", &""))
		Event.Kind.YEAR_STARTED:
			return "[b]—— 第 %d 财年开始 ——[/b]" % int(params.get("year", 0))
		Event.Kind.YEAR_ENDED:
			return "[b]—— 第 %d 财年结束 ——[/b]" % int(params.get("year", 0))
		Event.Kind.TURN_STARTED:
			return "回合 %d 开始" % int(params.get("turn_in_year", 0))
		Event.Kind.TURN_ENDED:
			return "回合结束"
		Event.Kind.CARD_PLAYED:
			return "打出卡牌：%s" % _card_name(params.get("card_id", &""))
		Event.Kind.CARD_GAINED:
			return "获得卡牌：%s" % _card_name(params.get("card_id", &""))
		Event.Kind.CARDS_DRAWN:
			return "抽牌 %d 张" % int(params.get("count", 0))
		Event.Kind.INDICATOR_CHANGED:
			return "%s：%s → %s（%s）" % [
				TextFormatter.indicator(_labels(), StringName(params.get("indicator", ""))),
				_fmt(float(params.get("previous", 0.0))),
				_fmt(float(params.get("current", 0.0))),
				_signed(float(params.get("delta", 0.0))),
			]
		Event.Kind.MODIFIER_APPLIED:
			return "修正生效：%s（%s）来源 %s" % [
				TextFormatter.indicator(_labels(), StringName(params.get("target", ""))),
				_op_word(int(params.get("op", 0))),
				params.get("source", ""),
			]
		Event.Kind.MODIFIER_EXPIRED:
			return "修正到期：%s 来源 %s" % [
				TextFormatter.indicator(_labels(), StringName(params.get("target", ""))),
				params.get("source", ""),
			]
		Event.Kind.RESOURCE_CHANGED:
			return "%s %s" % [
				TextFormatter.resource(_labels(), StringName(params.get("resource", ""))),
				_signed(float(params.get("amount", 0.0))),
			]
		Event.Kind.EVENT_TRIGGERED:
			return "[color=orange]事件：%s[/color]" % params.get("title", "")
		Event.Kind.EVENT_RESOLVED:
			return "事件处理完毕"
		Event.Kind.CABINET_APPOINTED:
			return "任命内阁：%s" % _cabinet_name(params.get("cabinet", &""))
		Event.Kind.AID_USED:
			return "使用援助：%s" % _aid_name(params.get("aid", &""))
		Event.Kind.AID_GAINED:
			return "获得援助：%s" % _aid_name(params.get("aid", &""))
		Event.Kind.BUDGET_OFFERED:
			return "请确定下一年度预算"
		Event.Kind.BUDGET_CHOSEN:
			return "已确定预算：%s" % _budget_name(params.get("plan", &""))
		Event.Kind.REWARD_OFFERED:
			return "财年奖励待选择"
		Event.Kind.REWARD_CHOSEN:
			return "已选择财年奖励"
		Event.Kind.RUN_WON:
			return "[b][color=green]胜利！[/color][/b]"
		Event.Kind.RUN_LOST:
			return "[b][color=red]失败：%s[/color][/b]" % params.get("reason", "")
	return ""


func _busy() -> bool:
	return _state.pending_event != &"" or not _state.pending_budget_plans.is_empty() or not _state.pending_rewards.is_empty()


func _turns_per_year() -> int:
	return int(controller.rules.get("turns_per_year", 0))


func _status_text() -> String:
	match _state.run_status:
		GameState.RunStatus.WON:
			return "已达成"
		GameState.RunStatus.LOST:
			return "已失败"
	return "进行中"


func _status_color() -> Color:
	match _state.run_status:
		GameState.RunStatus.WON:
			return UiTheme.POSITIVE
		GameState.RunStatus.LOST:
			return UiTheme.NEGATIVE
	return UiTheme.ACCENT_DARK


func _indicator_summary() -> String:
	var parts := PackedStringArray()
	for id in controller.simulation.economy.indicator_ids:
		parts.append("%s=%s" % [TextFormatter.indicator(_labels(), id), _fmt(controller.simulation.economy.value(_state, id))])
	for id in controller.simulation.economy.derived_ids:
		parts.append("%s=%s" % [TextFormatter.indicator(_labels(), id), _fmt(controller.simulation.economy.value(_state, id))])
	return "，".join(parts)


func _card_name(id: StringName) -> String:
	var card: CardDef = controller.cards.get(id)
	return card.display_name if card != null else String(id)


func _cabinet_name(id: StringName) -> String:
	var cabinet: CabinetDef = controller.cabinets.get(id)
	return cabinet.display_name if cabinet != null else String(id)


func _aid_name(id: StringName) -> String:
	var aid: AidDef = controller.aids.get(id)
	return aid.display_name if aid != null else String(id)


func _budget_name(id: StringName) -> String:
	var plan: BudgetPlanDef = controller.budgets.get(id)
	return plan.display_name if plan != null else String(id)


func _scenario_name(id: StringName) -> String:
	var scenario: ScenarioDef = controller.scenarios.get(id)
	return scenario.display_name if scenario != null else String(id)


func _labels() -> Dictionary:
	return controller.labels


func _colored(text: String, color: Color) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", color)
	return label


func _wrapped(text: String, color: Color, width: float = 220.0) -> Label:
	var label := _colored(text, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _op_word(op: int) -> String:
	match op:
		Modifier.Op.ADD:
			return "增加"
		Modifier.Op.MUL:
			return "乘以"
		Modifier.Op.OVERRIDE:
			return "设为"
	return "?"


func _reward_detail(reward: Reward) -> String:
	match reward.type:
		Reward.Type.CARD:
			var card: CardDef = controller.cards.get(reward.id)
			if card != null:
				return "［%s］\n%s" % [
					TextFormatter.card_type_name(_labels(), card.card_type),
					_detail_text(card.description, card.effects, controller.simulation.groups_of("cards", card.id)),
				]
		Reward.Type.CABINET:
			var cabinet: CabinetDef = controller.cabinets.get(reward.id)
			if cabinet != null:
				return _detail_text(cabinet.description, cabinet.modifiers, controller.simulation.groups_of("cabinets", cabinet.id))
		Reward.Type.AID:
			var aid: AidDef = controller.aids.get(reward.id)
			if aid != null:
				return _detail_text(aid.description, aid.effects, controller.simulation.groups_of("aids", aid.id))
	return ""


func _detail_text(description: String, effects: Array, group_ids: Array = []) -> String:
	var parts := PackedStringArray()
	if not group_ids.is_empty():
		parts.append("所属组：%s" % _group_names(group_ids))
	if description != "":
		parts.append(description)
	if not effects.is_empty():
		parts.append("具体作用：" + TextFormatter.effects_text(_labels(), effects))
	return "\n".join(parts)


func _group_names(group_ids: Array) -> String:
	var parts := PackedStringArray()
	for group_id in group_ids:
		var group: GroupDef = controller.groups.get(group_id)
		parts.append(group.display_name if group != null and group.display_name != "" else String(group_id))
	return "，".join(parts)


func _signed(value: float) -> String:
	return "+%s" % _fmt(value) if value >= 0.0 else _fmt(value)


func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
