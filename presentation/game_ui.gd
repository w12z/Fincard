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
var _statuses_box: VBoxContainer
var _indicators_box: VBoxContainer
var _effect_icons: HBoxContainer
var _cabinets_box: HBoxContainer
var _cabinet_bar: PanelContainer
var _aids_box: HBoxContainer
var _hand_box: HBoxContainer
var _hand_scroll: ScrollContainer
var _played_table: CardTable
var _table_section: VBoxContainer
var _deck_label: Label
var _end_turn_button: Button
var _log: RichTextLabel
var _sidebar: VBoxContainer
var _sidebar_button: Button
var _forecast: RichTextLabel
var _parameters: RichTextLabel
var _overlay_root: CenterContainer
var _overlay_box: VBoxContainer
var _overlay_panel: PanelContainer

var _log_lines: Array[String] = []
var _reward_selection: Dictionary = {}


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
	_build_cabinet_bar(root)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
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

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	_table_section = _make_section(center, "本回合出牌", true)
	_table_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var table_scroll := ScrollContainer.new()
	table_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_section.add_child(table_scroll)
	_played_table = CardTable.new()
	_played_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_played_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_scroll.add_child(_played_table)
	var hand_section := _make_section(center, "手牌")
	_hand_scroll = ScrollContainer.new()
	_hand_scroll.custom_minimum_size.y = 260
	_hand_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_section.add_child(_hand_scroll)
	_hand_box = HBoxContainer.new()
	_hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_box.add_theme_constant_override("separation", 10)
	var hand_margin := MarginContainer.new()
	hand_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_margin.add_theme_constant_override("margin_top", 14)
	_hand_scroll.add_child(hand_margin)
	hand_margin.add_child(_hand_box)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	center.add_child(footer)
	_deck_label = Label.new()
	_deck_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_deck_label)
	_sidebar_button = Button.new()
	_sidebar_button.text = "显示日志"
	_sidebar_button.toggled.connect(_toggle_sidebar)
	_sidebar_button.toggle_mode = true
	footer.add_child(_sidebar_button)
	_end_turn_button = Button.new()
	_end_turn_button.text = "结束回合"
	_end_turn_button.custom_minimum_size = Vector2(140, 40)
	_end_turn_button.theme_type_variation = "PrimaryButton"
	_end_turn_button.pressed.connect(func() -> void: _dispatch(Command.end_turn()))
	footer.add_child(_end_turn_button)

	_sidebar = VBoxContainer.new()
	_sidebar.custom_minimum_size = Vector2(300, 0)
	_sidebar.visible = false
	split.add_child(_sidebar)
	var forecast_section := _make_section(_sidebar, "结算预测", true)
	forecast_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var forecast_scroll := ScrollContainer.new()
	forecast_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	forecast_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	forecast_section.add_child(forecast_scroll)
	var forecast_content := VBoxContainer.new()
	forecast_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forecast_scroll.add_child(forecast_content)
	_forecast = RichTextLabel.new()
	_forecast.bbcode_enabled = true
	_forecast.fit_content = true
	_forecast.scroll_active = false
	_forecast.custom_minimum_size.x = 280
	forecast_content.add_child(_forecast)
	var parameter_button := Button.new()
	parameter_button.text = "规则与边界"
	parameter_button.toggle_mode = true
	forecast_content.add_child(parameter_button)
	_parameters = RichTextLabel.new()
	_parameters.bbcode_enabled = true
	_parameters.fit_content = true
	_parameters.scroll_active = false
	_parameters.visible = false
	forecast_content.add_child(_parameters)
	parameter_button.toggled.connect(func(pressed: bool) -> void: _parameters.visible = pressed)
	var log_section := _make_section(_sidebar, "事件日志", true)
	log_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(240, 0)
	log_section.add_child(_log)

	_build_overlay()


func _toggle_sidebar(pressed: bool) -> void:
	_sidebar.visible = pressed
	_sidebar_button.text = "收起日志" if pressed else "显示日志"
	if pressed:
		_render_log()


func _build_cabinet_bar(parent: VBoxContainer) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	parent.add_child(top)
	_cabinet_bar = PanelContainer.new()
	_cabinet_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_cabinet_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_cabinet_bar.add_child(row)
	row.add_child(_colored("内阁", UiTheme.ACCENT_DARK))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.custom_minimum_size.y = 84
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_cabinets_box = HBoxContainer.new()
	_cabinets_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_cabinets_box)
	_statuses_box = _make_section(top, "生效修正", false, 300)
	var aid_section := _make_section(top, "外部援助", false, 260)
	var aid_scroll := ScrollContainer.new()
	aid_scroll.custom_minimum_size = Vector2(230, 84)
	aid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	aid_section.add_child(aid_scroll)
	_aids_box = HBoxContainer.new()
	_aids_box.add_theme_constant_override("separation", 8)
	aid_scroll.add_child(_aids_box)


func _build_overlay() -> void:
	_overlay_root = CenterContainer.new()
	_overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.visible = false
	add_child(_overlay_root)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 650)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overlay_root.add_child(scroll)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(630, 0)
	_overlay_panel = panel
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)

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


func _make_section(parent: Control, title: String, expand: bool = false, minimum_width: float = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minimum_width
	if expand:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	_render_statuses()
	_render_indicators()
	_render_cabinets()
	_render_aids()
	_render_hand()
	_played_table.render(_state.played_cards_this_turn, controller.cards, _labels())
	_deck_label.text = "牌库 %d · 弃牌 %d · 手牌 %d" % [_state.deck.size(), _state.discard.size(), _state.hand.size()]
	_end_turn_button.disabled = _busy() or _state.run_status != GameState.RunStatus.RUNNING
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
	var budget_label := ResourceAmount.create(&"budget", "%d · 年入 %d" % [_state.budget, controller.simulation.annual_income()], UiTheme.NEGATIVE if _state.budget < 0 else UiTheme.ACCENT_DARK)
	budget_label.tooltip_text += "\n年度收入 %d · 余额结转 %d%%（向下取整）\n%s" % [controller.simulation.annual_income(), roundi(controller.simulation.budget_retention() * 100), "可透支" if StatusRules.allows_deficit(_state, controller.statuses) else "不可透支"]
	_header.add_child(budget_label)
	var political_label := ResourceAmount.create(&"political", str(_state.political_capital), UiTheme.POSITIVE)
	political_label.tooltip_text += "\n每回合重置为 %d 点，剩余点数不继承" % controller.simulation.political_capital_per_turn()
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
		var achieved := condition.evaluate(_state, controller.simulation.economy)
		_goal_box.add_child(_wrapped("%s %s" % ["✓" if achieved else "○", TextFormatter.condition_text(_labels(), condition)], UiTheme.POSITIVE if achieved else UiTheme.MUTED))
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
				TextFormatter.fmt(controller.simulation.economy.value(_state, id)),
			]))
	_indicators_box.tooltip_text = "每回合 1 个月 · 增长率按月计算"
	var derived := controller.simulation.economy.derived_ids
	if not derived.is_empty():
		_indicators_box.add_child(_colored("综合指标", UiTheme.WARNING))
		for id in derived:
			_indicators_box.add_child(_label("%s：%s" % [
				TextFormatter.indicator(_labels(), id),
				TextFormatter.fmt(controller.simulation.economy.value(_state, id)),
			]))


func _render_statuses() -> void:
	_clear(_statuses_box)
	_effect_icons = null
	var entries := ModifierDisplay.entries(controller.simulation, _labels())
	if entries.is_empty():
		_statuses_box.add_child(_label("（无）"))
		return
	_statuses_box.add_child(_label("本回合已出 %d 张牌" % _state.cards_played_this_turn))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 84)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_statuses_box.add_child(scroll)
	_effect_icons = HBoxContainer.new()
	_effect_icons.add_theme_constant_override("separation", 6)
	scroll.add_child(_effect_icons)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var badge := Button.new()
		badge.theme_type_variation = "StatusBadge"
		badge.custom_minimum_size = Vector2(60, 62)
		badge.text = "%s\n%s" % [entry["icon"], entry.get("value_text", entry["counter"])]
		badge.tooltip_text = entry["tooltip"]
		badge.set_meta("effect_key", entry["key"])
		UiTheme.style_modifier_badge(badge, index)
		_effect_icons.add_child(badge)


func _render_cabinets() -> void:
	_clear(_cabinets_box)
	if _state.cabinets.is_empty():
		_cabinets_box.add_child(_colored("（空缺）", UiTheme.MUTED))
		return
	for cabinet in _state.cabinets:
		var badge := CabinetPortrait.new()
		badge.setup(cabinet, _labels())
		_cabinets_box.add_child(badge)


func _render_aids() -> void:
	_clear(_aids_box)
	if _state.aids.is_empty():
		_aids_box.add_child(_label("（无）"))
		return
	for entry in _state.aids:
		var definition: AidDef = entry["def"]
		var use := Button.new()
		use.text = "%s\n×%d" % [definition.display_name, int(entry["uses"])]
		use.custom_minimum_size = Vector2(110, 64)
		use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		use.theme_type_variation = "AidButton"
		use.tooltip_text = "%s\n%s\n%s" % [definition.display_name, definition.description, TextFormatter.effects_text(_labels(), definition.effects)]
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
		var rarity_label := TextFormatter.rarity_name(_labels(), card.rarity)
		var type_color := UiTheme.card_type_color(card.card_type)
		var costs := controller.simulation.card_costs(card_id)
		var budget_text := str(costs["budget"])
		var political_text := str(costs["political"])
		if int(costs["budget"]) != card.cost:
			budget_text += "（原%d）" % card.cost
		if int(costs["political"]) != card.political_cost:
			political_text += "（原%d）" % card.political_cost
		var lines := PackedStringArray([
			card.display_name,
			"［%s］" % rarity_label,
			"［%s］" % type_label,
		])
		if card.once_per_run:
			lines.append("法案 · 限通过一次")
		for effect in card.effects:
			lines.append(TextFormatter.effects_text(_labels(), [effect]))
		for id in costs["sources"]:
			lines.append("★ " + controller.statuses[id].display_name + "减免")
		var button := CardButton.new()
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.preview_card = card
		button.preview_labels = _labels()
		button.tooltip_text = "%s［%s · %s］\n%s" % [card.display_name, rarity_label, type_label, _detail_text(card.description, card.effects, controller.simulation.groups_of("cards", card.id))]
		button.preview_budget = budget_text
		button.preview_political = political_text
		for id in costs["sources"]:
			button.tooltip_text += "\n★ " + controller.statuses[id].display_name + "减免"
		button.custom_minimum_size = Vector2(180, 240)
		button.add_theme_font_size_override("font_size", 13)
		button.theme_type_variation = "CardButton"
		button.disabled = _busy() or _state.run_status != GameState.RunStatus.RUNNING \
			or not controller.simulation.can_spend_budget(int(costs["budget"])) \
			or (int(costs["political"]) > 0 and _state.political_capital < int(costs["political"]))
		if not button.disabled:
			var playable_style := StyleBoxFlat.new()
			playable_style.bg_color = Color("effaf5")
			playable_style.border_color = UiTheme.POSITIVE
			playable_style.set_border_width_all(2)
			playable_style.set_corner_radius_all(10)
			playable_style.content_margin_left = 10
			playable_style.content_margin_right = 10
			playable_style.content_margin_top = 8
			playable_style.content_margin_bottom = 8
			button.add_theme_stylebox_override("normal", playable_style)
		button.pressed.connect(func() -> void: _dispatch(Command.play_card(card_id)))
		_hand_box.add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 10)
		button.add_child(margin)
		var content := VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(content)
		for index in lines.size():
			var line_color := type_color if index == 0 else (UiTheme.rarity_color(card.rarity) if index == 1 else UiTheme.TEXT)
			var line := _wrapped(lines[index], line_color, 0)
			line.name = "CardName" if index == 0 else ("Rarity" if index == 1 else "Detail%d" % index)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if index < 3 else HORIZONTAL_ALIGNMENT_LEFT
			line.add_theme_font_size_override("font_size", 13)
			content.add_child(line)
			if index == 1:
				var fees := HBoxContainer.new()
				fees.name = "Costs"
				fees.alignment = BoxContainer.ALIGNMENT_CENTER
				fees.add_theme_constant_override("separation", 10)
				fees.add_theme_font_size_override("font_size", 13)
				fees.add_child(ResourceAmount.create(&"budget", budget_text))
				fees.add_child(ResourceAmount.create(&"political", political_text))
				content.add_child(fees)
				button.custom_minimum_size.x = maxf(180, fees.get_combined_minimum_size().x + 20)
		content.modulate.a = 0.55 if button.disabled else 1.0
		content.minimum_size_changed.connect(func() -> void:
			button.custom_minimum_size.y = maxf(240, content.get_combined_minimum_size().y + 20)
		)
		_ignore_card_mouse(margin)
		button.enable_lift(margin)


func _ignore_card_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_card_mouse(child)


func _render_log() -> void:
	_log.text = "\n".join(_log_lines)
	_forecast.text = EconomyForecast.text(controller.simulation, _labels())
	_parameters.text = EconomyForecast.parameters(controller.simulation, _labels())


func _render_overlay() -> void:
	_clear(_overlay_box)
	_overlay_panel.theme_type_variation = "EventPanel" if _state.pending_event != &"" and _state.run_status == GameState.RunStatus.RUNNING else ""
	if _state.run_status != GameState.RunStatus.RUNNING:
		_show_result()
		return
	if _state.pending_event != &"":
		_show_event()
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
	title.add_theme_color_override("font_color", UiTheme.EVENT_ACCENT)
	_overlay_box.add_child(title)
	if definition != null and definition.description != "":
		_overlay_box.add_child(_wrapped(definition.description, UiTheme.TEXT, 460.0))
	if _state.pending_event_choices.is_empty():
		if definition != null and not definition.effects.is_empty():
			_overlay_box.add_child(_colored("影响", UiTheme.EVENT_ACCENT))
			_overlay_box.add_child(_wrapped(TextFormatter.effects_text(_labels(), definition.effects), UiTheme.TEXT, 460.0))
		var cont := Button.new()
		cont.text = "继续"
		cont.theme_type_variation = "EventChoice"
		cont.pressed.connect(func() -> void: _dispatch(Command.resolve_event(-1)))
		_overlay_box.add_child(cont)
	else:
		for index in range(_state.pending_event_choices.size()):
			var choice: Dictionary = _state.pending_event_choices[index]
			var button := Button.new()
			button.theme_type_variation = "EventChoice"
			var text := str(choice.get("label", "..."))
			if definition != null and index < definition.choices.size() and not definition.choices[index].effects.is_empty():
				text += "\n" + TextFormatter.effects_text(_labels(), definition.choices[index].effects)
			button.text = text
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.tooltip_text = choice.get("description", "")
			button.disabled = not controller.simulation.event_choice_available(index)
			if button.disabled:
				button.tooltip_text += "\n预算不足"
			var choice_index := index
			button.pressed.connect(func() -> void: _dispatch(Command.resolve_event(choice_index)))
			_overlay_box.add_child(button)
	_overlay_root.visible = true


func _show_rewards() -> void:
	_reward_selection.clear()
	var title := Label.new()
	title.text = "年度筹备 · 每组可选一项"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_overlay_box.add_child(title)
	var odds := _wrapped("卡牌／内阁出现权重  普通 %s · 稀有 %s · 传奇 %s" % [TextFormatter.fmt(controller.simulation.rarity_weight(&"common")), TextFormatter.fmt(controller.simulation.rarity_weight(&"rare")), TextFormatter.fmt(controller.simulation.rarity_weight(&"legendary"))], UiTheme.MUTED, 460.0)
	_overlay_box.add_child(odds)
	for group_index in range(_state.pending_rewards.size()):
		var group: Dictionary = _state.pending_rewards[group_index]
		var group_title := _label(str(TYPE_LABELS.get(group.get("type"), "奖励")))
		_overlay_box.add_child(group_title)
		var options: Array = group.get("options", [])
		var button_group := ButtonGroup.new()
		for option_index in range(options.size()):
			var reward: Reward = options[option_index]
			var check := CardPreview.RewardChoice.new()
			check.text = reward.label
			check.tooltip_text = _reward_detail(reward)
			if reward.type == Reward.Type.CARD:
				var reward_card: CardDef = controller.cards.get(reward.id)
				if reward_card != null:
					check.is_card = true
					check.preview_card = reward_card
					check.preview_labels = _labels()
					check.preview_budget = str(reward_card.cost)
					check.preview_political = str(reward_card.political_cost)
					check.text = ""
					var reward_content := HBoxContainer.new()
					reward_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
					reward_content.offset_left = 28
					reward_content.offset_right = -4
					reward_content.add_child(CardPreview.name_label(reward_card))
					reward_content.add_child(CardPreview.rarity_label(reward_card, _labels()))
					check.add_child(reward_content)
					check.custom_minimum_size = reward_content.get_combined_minimum_size() + Vector2(32, 8)
					_ignore_card_mouse(reward_content)
			check.button_group = button_group
			var gi := group_index
			var oi := option_index
			check.toggled.connect(func(pressed: bool) -> void:
				if pressed:
					_reward_selection[gi] = oi
			)
			if reward.type == Reward.Type.CABINET and controller.cabinets.has(reward.id):
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 12)
				var badge := CabinetPortrait.new()
				badge.setup(controller.cabinets[reward.id], _labels())
				badge.pressed.connect(func() -> void: check.button_pressed = true)
				row.add_child(badge)
				row.add_child(check)
				var cabinet_rarity := _colored(badge.rarity_text, UiTheme.rarity_color(badge.rarity))
				row.add_child(cabinet_rarity)
				_overlay_box.add_child(row)
			else:
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
	title.text = "目标达成" if won else "计划失败"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.POSITIVE if won else UiTheme.NEGATIVE)
	_overlay_box.add_child(title)
	var info := _label("第 %d 财年 · %s" % [_state.year, _indicator_summary()])
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(460, 0)
	_overlay_box.add_child(info)
	if not won:
		var reason := "任期届满，目标未达成。" if _state.flags.get("loss_reason", "") == "deadline" else "经济危机导致计划终止。"
		_overlay_box.add_child(_wrapped(reason, UiTheme.NEGATIVE, 460.0))
	_overlay_box.add_child(_label("复盘种子：%d · 总回合：%d" % [_state.seed_value, _state.turn]))
	var back := Button.new()
	back.text = "返回菜单"
	back.custom_minimum_size = Vector2(0, 36)
	back.theme_type_variation = "PrimaryButton"
	back.pressed.connect(func() -> void: exit_requested.emit())
	_overlay_box.add_child(back)
	_overlay_root.visible = true


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
	var name := TextFormatter.event_name(_labels(), Event.name_of(event.kind))
	match event.kind:
		Event.Kind.RUN_STARTED:
			return "[b]%s：%s[/b]" % [name, _display_name(controller.scenarios, params.get("scenario", &""))]
		Event.Kind.YEAR_STARTED:
			return "[b]—— 第 %d 财年开始 ——[/b]" % int(params.get("year", 0))
		Event.Kind.YEAR_ENDED:
			return "[b]—— 第 %d 财年结束 ——[/b]" % int(params.get("year", 0))
		Event.Kind.TURN_STARTED:
			return "%s %d" % [name, int(params.get("turn_in_year", 0))]
		Event.Kind.TURN_ENDED:
			return name
		Event.Kind.CARD_PLAYED:
			return "%s：%s" % [name, _display_name(controller.cards, params.get("card_id", &""))]
		Event.Kind.CARD_GAINED:
			return "%s：%s" % [name, _display_name(controller.cards, params.get("card_id", &""))]
		Event.Kind.CARDS_DRAWN:
			return "%s %d 张" % [name, int(params.get("count", 0))]
		Event.Kind.INDICATOR_CHANGED:
			return "%s：%s → %s（%s）" % [
				TextFormatter.indicator(_labels(), StringName(params.get("indicator", ""))),
				TextFormatter.fmt(float(params.get("previous", 0.0))),
				TextFormatter.fmt(float(params.get("current", 0.0))),
				TextFormatter.signed(float(params.get("delta", 0.0))),
			]
		Event.Kind.MODIFIER_APPLIED:
			return "%s：%s（%s）来源 %s" % [
				name,
				TextFormatter.modifier_target(_labels(), StringName(params.get("scope", "indicator")), StringName(params.get("target", ""))),
				Modifier.op_label(int(params.get("op", 0))),
				params.get("source", ""),
			]
		Event.Kind.MODIFIER_EXPIRED:
			return "%s：%s 来源 %s" % [
				name,
				TextFormatter.modifier_target(_labels(), StringName(params.get("scope", "indicator")), StringName(params.get("target", ""))),
				params.get("source", ""),
			]
		Event.Kind.RESOURCE_CHANGED:
			return "%s %s" % [
				TextFormatter.resource(_labels(), StringName(params.get("resource", ""))),
				TextFormatter.signed(float(params.get("amount", 0.0))),
			]
		Event.Kind.EVENT_TRIGGERED:
			return "[color=orange]%s：%s[/color]" % [name, params.get("title", "")]
		Event.Kind.EVENT_RESOLVED:
			return name
		Event.Kind.CABINET_APPOINTED:
			return "%s：%s" % [name, _display_name(controller.cabinets, params.get("cabinet", &""))]
		Event.Kind.AID_USED:
			return "%s：%s" % [name, _display_name(controller.aids, params.get("aid", &""))]
		Event.Kind.AID_GAINED:
			return "%s：%s" % [name, _display_name(controller.aids, params.get("aid", &""))]
		Event.Kind.STATUS_GAINED, Event.Kind.STATUS_TRIGGERED:
			return "[color=#7a3fb0]%s：%s[/color]" % ["获得能力" if event.kind == Event.Kind.STATUS_GAINED else "能力触发", _display_name(controller.statuses, params.get("status", &""))]
		Event.Kind.REWARD_OFFERED:
			return name
		Event.Kind.REWARD_CHOSEN:
			return name
		Event.Kind.RUN_WON:
			return "[b][color=green]%s！[/color][/b]" % name
		Event.Kind.RUN_LOST:
			return "[b][color=red]%s：%s[/color][/b]" % [name, "任期结束" if params.get("reason", "") == "deadline" else "触发经济崩溃条件"]
	return ""


func _busy() -> bool:
	return _state.pending_event != &"" or not _state.pending_rewards.is_empty()


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
		parts.append("%s=%s" % [TextFormatter.indicator(_labels(), id), TextFormatter.fmt(controller.simulation.economy.value(_state, id))])
	for id in controller.simulation.economy.derived_ids:
		parts.append("%s=%s" % [TextFormatter.indicator(_labels(), id), TextFormatter.fmt(controller.simulation.economy.value(_state, id))])
	return "，".join(parts)


func _display_name(db: Dictionary, id: StringName) -> String:
	var definition = db.get(id)
	if definition != null and "display_name" in definition and str(definition.display_name) != "":
		return str(definition.display_name)
	return String(id)


func _labels() -> Dictionary:
	return controller.labels


func _colored(text: String, color: Color) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", color)
	return label


func _wrapped(text: String, color: Color, width: float = 200.0) -> Label:
	var label := _colored(text, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _reward_detail(reward: Reward) -> String:
	match reward.type:
		Reward.Type.CARD:
			var card: CardDef = controller.cards.get(reward.id)
			if card != null:
				return "［%s · %s］\n%s" % [
					TextFormatter.rarity_name(_labels(), card.rarity), TextFormatter.card_type_name(_labels(), card.card_type),
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
		parts.append("类别：%s" % _group_names(group_ids))
	if description != "":
		parts.append(description)
	if not effects.is_empty():
		parts.append(TextFormatter.effects_text(_labels(), effects))
	return "\n".join(parts)


func _group_names(group_ids: Array) -> String:
	var parts := PackedStringArray()
	for group_id in group_ids:
		var group: GroupDef = controller.groups.get(group_id)
		parts.append(group.display_name if group != null and group.display_name != "" else String(group_id))
	return "，".join(parts)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
