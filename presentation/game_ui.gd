class_name GameUI
extends Control

signal exit_requested

const LOG_LIMIT := 1000
const UNSET_SIGNATURE := "__unset__"
const CARD_FLIGHT_DURATION := 0.2
const CARD_FLIGHT_SETTLE_FRAMES := 4
const TYPE_LABELS := {
	Reward.Type.CARD: "新卡牌",
	Reward.Type.CABINET: "任命内阁",
	Reward.Type.AID: "申请援助",
}

var controller: GameController
var _state: GameState
var _game_page: MarginContainer
var _meeting_page: FiscalMeeting

var _header: HBoxContainer
var _goal_box: VBoxContainer
var _goal_section: Control
var _goal_button: Button
var _statuses_box: VBoxContainer
var _indicators_box: VBoxContainer
var _effect_icons: GridContainer
var _cabinets_box: HBoxContainer
var _cabinet_bar: PanelContainer
var _aids_box: HBoxContainer
var _aids_title: Label
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
var _flight_layer: Control
var _effect_feedback: EffectFeedback
var _pending_effect_feedback: Array[Dictionary] = []
var _turn_settlement: TurnSettlement
var _settlement_active := false
var _presentation_generation := 0
var _cleared_turn := -1

var _flight_card: CardButton
var _flight_target: Control
var _flight_tween: Tween
var _flight_active: bool = false
var _flight_generation: int = 0
var _automatic_flights: Array[Dictionary] = []

var _log_lines: Array[String] = []
var _reward_group_index: int = -1

var _year_label: Label
var _turn_label: Label
var _budget_amount: ResourceAmount
var _political_amount: ResourceAmount
var _status_label: Label
var _indicator_rows: Array[Dictionary] = []
var _log_rendered_lines: int = 0
var _built: bool = false

var _goal_signature: String = UNSET_SIGNATURE
var _indicator_structure: String = UNSET_SIGNATURE
var _status_signature: String = UNSET_SIGNATURE
var _cabinet_signature: String = UNSET_SIGNATURE
var _aids_signature: String = UNSET_SIGNATURE
var _hand_signature: String = UNSET_SIGNATURE
var _overlay_signature: String = UNSET_SIGNATURE
var _forecast_signature: String = UNSET_SIGNATURE
var _forecast_dirty: bool = true
var _forecast_build_count: int = 0


func setup(p_controller: GameController, scenario_id: StringName) -> void:
	_presentation_generation += 1
	_settlement_active = false
	_cleared_turn = -1
	if is_instance_valid(_turn_settlement):
		_turn_settlement.clear()
	_cancel_flight(false)
	_pending_effect_feedback.clear()
	if _built:
		for child in get_children():
			remove_child(child)
			child.queue_free()
	controller = p_controller
	_log_lines.clear()
	_log_rendered_lines = 0
	_reward_group_index = -1
	_effect_icons = null
	_indicator_rows.clear()
	_forecast_build_count = 0
	_build()
	_reset_section_signatures()
	_play_events(controller.start_run(scenario_id))
	_render()


func _reset_section_signatures() -> void:
	_goal_signature = UNSET_SIGNATURE
	_indicator_structure = UNSET_SIGNATURE
	_status_signature = UNSET_SIGNATURE
	_cabinet_signature = UNSET_SIGNATURE
	_aids_signature = UNSET_SIGNATURE
	_hand_signature = UNSET_SIGNATURE
	_overlay_signature = UNSET_SIGNATURE
	_forecast_signature = UNSET_SIGNATURE
	_forecast_dirty = true


func _build() -> void:
	var margin := MarginContainer.new()
	_game_page = margin
	_game_page.name = "GamePage"
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
	_build_header_contents()
	_build_cabinet_bar(root)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(260, 0)
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left)
	_indicators_box = _make_section(left, "经济指标")
	var forecast_section := _make_section(left, "下回合预测")
	var forecast_content := VBoxContainer.new()
	forecast_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forecast_section.add_child(forecast_content)
	_forecast = RichTextLabel.new()
	_forecast.bbcode_enabled = true
	_forecast.fit_content = true
	_forecast.scroll_active = false
	_forecast.custom_minimum_size.x = 230
	forecast_content.add_child(_forecast)
	var formula_button := Button.new()
	formula_button.text = "结算公式与规则"
	formula_button.toggle_mode = true
	forecast_content.add_child(formula_button)
	_parameters = RichTextLabel.new()
	_parameters.bbcode_enabled = true
	_parameters.fit_content = true
	_parameters.scroll_active = false
	_parameters.visible = false
	forecast_content.add_child(_parameters)
	formula_button.toggled.connect(func(pressed: bool) -> void: _parameters.visible = pressed)
	_goal_button = Button.new()
	_goal_button.text = "最终目标"
	_goal_button.toggle_mode = true
	left.add_child(_goal_button)
	_goal_box = _make_section(left, "最终目标")
	_goal_section = _goal_box.get_parent().get_parent().get_parent()
	_goal_section.visible = false
	_goal_button.toggled.connect(func(pressed: bool) -> void: _goal_section.visible = pressed)

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
	_hand_scroll.custom_minimum_size.y = 310
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
	var log_section := _make_section(_sidebar, "事件日志", true)
	log_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	ImpactText.configure(_log)
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(240, 0)
	log_section.add_child(_log)

	_flight_layer = Control.new()
	_flight_layer.name = "CardFlightLayer"
	_flight_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flight_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flight_layer)
	_effect_feedback = EffectFeedback.new()
	add_child(_effect_feedback)

	_meeting_page = FiscalMeeting.new()
	_meeting_page.visible = false
	_meeting_page.exit_requested.connect(func() -> void: exit_requested.emit())
	add_child(_meeting_page)
	_build_overlay()
	_turn_settlement = TurnSettlement.new()
	add_child(_turn_settlement)
	_built = true


func _build_header_contents() -> void:
	var title := Label.new()
	title.text = "Fincard"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_header.add_child(title)
	_header.add_child(SfxAudio.controls(self))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)
	_year_label = _label("")
	_header.add_child(_year_label)
	_turn_label = _label("")
	_header.add_child(_turn_label)
	_budget_amount = ResourceAmount.create(&"budget", "0")
	_header.add_child(_budget_amount)
	_political_amount = ResourceAmount.create(&"political", "0", UiTheme.POSITIVE)
	_header.add_child(_political_amount)
	_status_label = _label("")
	_header.add_child(_status_label)
	var back := Button.new()
	back.text = "返回菜单"
	back.pressed.connect(func() -> void: exit_requested.emit())
	_header.add_child(back)


func _toggle_sidebar(pressed: bool) -> void:
	_sidebar.visible = pressed
	_sidebar_button.text = "收起日志" if pressed else "显示日志"
	if pressed:
		_sync_log()
		_scroll_log_to_end()


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
	_aids_title = aid_section.get_parent().get_child(0)
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
	if _settlement_active:
		return
	_state = controller.simulation.state
	var meeting := _is_annual_meeting()
	_game_page.visible = not meeting
	_flight_layer.visible = not meeting
	_effect_feedback.visible = not meeting
	_meeting_page.visible = meeting
	if meeting:
		if _flight_active:
			_cancel_flight(true)
		_meeting_page.update_context(controller)
		_render_overlay()
		return
	_render_header()
	_render_goal()
	_render_statuses()
	_render_indicators()
	_render_cabinets()
	_render_aids()
	_render_hand()
	var shown_history: Array[StringName] = []
	if _state.turn != _cleared_turn:
		shown_history.assign(_state.played_cards_this_turn)
	_played_table.render(shown_history, controller.cards, _labels(), _state.flags.get("automatic_play_orders", []))
	if _flight_active and _flight_target != null \
		and (not is_instance_valid(_flight_target) or _flight_target.get_parent() != _played_table):
		# The table rebuilt mid-flight; drop the temporary card instead of ghosting it.
		_cancel_flight(true)
	var deck_text := "牌库 %d · 弃牌 %d · 手牌 %d" % [_state.deck.size(), _state.discard.size(), _state.hand.size()]
	if _deck_label.text != deck_text:
		_deck_label.text = deck_text
	_end_turn_button.disabled = _busy() or _flight_active or _state.run_status != GameState.RunStatus.RUNNING
	_render_log()
	_render_overlay()


func _render_header() -> void:
	var income := controller.simulation.annual_income()
	var retention := roundi(controller.simulation.budget_retention() * 100)
	var year_text := "第 %d 财年" % _state.year
	if _year_label.text != year_text:
		_year_label.text = year_text
	var turn_text := "回合 %d/%d" % [_state.turn_in_year, _turns_per_year()]
	if _turn_label.text != turn_text:
		_turn_label.text = turn_text
	_set_resource_amount(_budget_amount, "%d · 年入 %d" % [_state.budget, income], UiTheme.NEGATIVE if _state.budget < 0 else UiTheme.ACCENT_DARK)
	var budget_tooltip := "预算\n年度收入 %d\n余额结转 %d%%\n%s" % [income, retention, "最低预算 %d" % controller.simulation.budget_floor() if StatusRules.allows_deficit(_state, controller.statuses) else "不可透支"]
	if _budget_amount.tooltip_text != budget_tooltip:
		_budget_amount.tooltip_text = budget_tooltip
	_set_resource_amount(_political_amount, str(_state.political_capital), UiTheme.POSITIVE)
	var political_tooltip := "政治行动点\n每回合重置为 %d 点" % controller.simulation.political_capital_per_turn()
	if _political_amount.tooltip_text != political_tooltip:
		_political_amount.tooltip_text = political_tooltip
	var status_text := "状态：%s" % _status_text()
	if _status_label.text != status_text:
		_status_label.text = status_text
	var status_color := _status_color()
	if _status_label.get_theme_color("font_color") != status_color:
		_status_label.add_theme_color_override("font_color", status_color)


func _set_resource_amount(display: ResourceAmount, text: String, color: Color) -> void:
	var amount: Label = display.get_node("Amount")
	if amount.text != text:
		amount.text = text
	if amount.get_theme_color("font_color") != color:
		amount.add_theme_color_override("font_color", color)


func _render_goal() -> void:
	var rows: Array[Dictionary] = []
	var scenario: ScenarioDef = controller.scenarios.get(_state.scenario_id)
	if scenario == null or scenario.goal == null:
		rows.append({"text": "（无）", "plain": true})
	else:
		var goal := scenario.goal
		for condition in goal.conditions:
			var achieved := condition.evaluate(_state, controller.simulation.economy)
			rows.append({
				"text": "%s %s" % ["✓" if achieved else "○", TextFormatter.condition_text(_labels(), condition)],
				"color": UiTheme.POSITIVE if achieved else UiTheme.MUTED,
				"wrap": true,
			})
		for condition in goal.loss_conditions:
			rows.append({"text": "失败：%s" % TextFormatter.condition_text(_labels(), condition), "color": UiTheme.NEGATIVE, "wrap": true})
		if goal.deadline_years > 0:
			rows.append({"text": "期限：第 %d 财年" % goal.deadline_years, "color": UiTheme.WARNING})
		if goal.after_turn > 0:
			rows.append({"text": "胜利判定：自第 %d 回合起" % (goal.after_turn + 1), "color": UiTheme.WARNING})
	var signature := _rows_signature(rows)
	if signature == _goal_signature:
		return
	_goal_signature = signature
	_clear(_goal_box)
	_add_rows(_goal_box, rows)


func _rows_signature(rows: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for row in rows:
		if row.get("plain", false):
			parts.append("%s|plain" % str(row["text"]))
		else:
			var color: Color = row["color"]
			parts.append("%s|%s|%s" % [str(row["text"]), color.to_html(), str(row.get("wrap", false))])
	return "\n".join(parts)


func _add_rows(box: VBoxContainer, rows: Array[Dictionary]) -> void:
	for row in rows:
		if row.get("plain", false):
			box.add_child(_label(str(row["text"])))
		elif row.get("wrap", false):
			box.add_child(_wrapped(str(row["text"]), row["color"]))
		else:
			box.add_child(ImpactText.create(str(row["text"]), row["color"]))


func _render_indicators() -> void:
	var economy := controller.simulation.economy
	var ids := economy.indicator_ids
	var derived := economy.derived_ids
	var structure := "%s|%s" % [var_to_str(ids), var_to_str(derived)]
	if structure != _indicator_structure:
		_indicator_structure = structure
		_clear(_indicators_box)
		_indicator_rows.clear()
		if ids.is_empty():
			_indicators_box.add_child(_label("（未定义指标）"))
		else:
			for id in ids:
				_add_indicator_row(id)
		if not derived.is_empty():
			_indicators_box.add_child(_colored("综合指标", UiTheme.WARNING))
			for id in derived:
				_add_indicator_row(id)
	for row in _indicator_rows:
		var label: Label = row["label"]
		var id: StringName = row["id"]
		var value_text := "%s：%s" % [TextFormatter.indicator(_labels(), id), TextFormatter.fmt(economy.value(_state, id))]
		if label.text != value_text:
			label.text = value_text


func _add_indicator_row(id: StringName) -> void:
	var label := _label("")
	_indicators_box.add_child(label)
	_indicator_rows.append({"id": id, "label": label})


func _render_statuses() -> void:
	var entries := ModifierDisplay.entries(controller.simulation, _labels())
	var signature := _statuses_signature(entries)
	if signature == _status_signature:
		return
	_status_signature = signature
	_clear(_statuses_box)
	_effect_icons = null
	if entries.is_empty():
		_statuses_box.add_child(_label("（无）"))
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 28)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_statuses_box.add_child(scroll)
	_effect_icons = GridContainer.new()
	_effect_icons.columns = 9
	_effect_icons.add_theme_constant_override("separation", 4)
	_effect_icons.add_theme_constant_override("h_separation", 4)
	_effect_icons.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_effect_icons)
	scroll.resized.connect(_layout_modifier_icons)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var badge := ModifierDisplay.Badge.new()
		badge.theme_type_variation = "StatusBadge"
		badge.custom_minimum_size = Vector2(24, 24)
		badge.text = ""
		badge.tooltip_text = entry["tooltip"]
		badge.set_meta("effect_key", entry["key"])
		UiTheme.style_modifier_badge(badge, index)
		_effect_icons.add_child(badge)
		var icon := TextureRect.new()
		icon.texture = ArtAssets.modifier_icon(str(entry["icon"]))
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 3
		icon.offset_top = 3
		icon.offset_right = -3
		icon.offset_bottom = -3
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(icon)
	_layout_modifier_icons()


func _layout_modifier_icons() -> void:
	if not is_instance_valid(_effect_icons):
		return
	var scroll := _effect_icons.get_parent() as ScrollContainer
	var count := _effect_icons.get_child_count()
	var per_row := maxi(1, int((maxf(280, scroll.size.x) + 4) / 28))
	# Fill available width first; only grow horizontally once three rows are full.
	_effect_icons.columns = maxi(per_row, ceili(count / 3.0))
	var rows := mini(3, ceili(float(count) / _effect_icons.columns))
	scroll.custom_minimum_size.y = maxi(28, rows * 28 - 4) + (14 if count > per_row * 3 else 0)


func _statuses_signature(entries: Array[Dictionary]) -> String:
	var parts := PackedStringArray(["cards:%d" % _state.cards_played_this_turn])
	for entry in entries:
		parts.append("%s|%s|%s|%s|%s" % [
			entry["key"],
			entry["icon"],
			str(entry.get("value_text", entry["counter"])),
			str(entry["counter"]),
			entry["tooltip"],
		])
	return "\n".join(parts)


func _render_cabinets() -> void:
	var ids := PackedStringArray()
	for cabinet in _state.cabinets:
		ids.append(String(cabinet.id))
	var signature := "|".join(ids)
	if signature == _cabinet_signature:
		return
	_cabinet_signature = signature
	_clear(_cabinets_box)
	if _state.cabinets.is_empty():
		_cabinets_box.add_child(_colored("（空缺）", UiTheme.MUTED))
		return
	for cabinet in _state.cabinets:
		var badge := CabinetPortrait.new()
		badge.setup(cabinet, _labels())
		_cabinets_box.add_child(badge)


func _render_aids() -> void:
	var sim := controller.simulation
	_aids_title.text = "外部援助 %d/%d" % [sim.aid_count(), sim.aid_capacity()]
	var parts := PackedStringArray([str(_busy()), str(_state.run_status), str(sim.aid_capacity())])
	for entry in _state.aids:
		var definition: AidDef = entry["def"]
		parts.append("%s:%d" % [definition.id, int(entry["uses"])])
	var signature := "\n".join(parts)
	if signature == _aids_signature:
		return
	_aids_signature = signature
	_clear(_aids_box)
	if _state.aids.is_empty():
		_aids_box.add_child(_label("（无）"))
		return
	for entry in _state.aids:
		var definition: AidDef = entry["def"]
		var use := ImpactButton.new()
		use.text = definition.display_name
		use.custom_minimum_size = Vector2(110, 64)
		use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		use.theme_type_variation = "AidButton"
		use.tooltip_text = "%s\n%s" % [definition.display_name, TextFormatter.effects_text(_labels(), definition.effects)]
		use.disabled = _busy() or _state.run_status != GameState.RunStatus.RUNNING
		var aid_id: StringName = definition.id
		use.pressed.connect(func() -> void: _dispatch(Command.use_aid(aid_id)))
		_aids_box.add_child(use)


func _render_hand() -> void:
	if _state.turn == _cleared_turn:
		_clear(_hand_box)
		_hand_signature = UNSET_SIGNATURE
		return
	var signature := _hand_content_signature()
	if signature == _hand_signature:
		return
	_hand_signature = signature
	_clear(_hand_box)
	if _state.hand.is_empty():
		_hand_box.add_child(_label("（无手牌）"))
		_hand_scroll.custom_minimum_size.y = 310
		return
	for card_id in _state.hand:
		var card: CardDef = controller.cards.get(card_id)
		if card == null:
			continue
		var costs := controller.simulation.card_costs(card_id)
		var budget_text := str(costs["budget"])
		var political_text := str(costs["political"])
		if int(costs["budget"]) != card.cost:
			budget_text += "（原%d）" % card.cost
		if int(costs["political"]) != card.political_cost:
			political_text += "（原%d）" % card.political_cost
		var sources: Array[String] = []
		for id in costs["sources"]:
			sources.append(controller.statuses[id].display_name)
		var button := CardButton.new()
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.preview_card = card
		button.preview_labels = _labels()
		button.tooltip_text = "%s\n%s" % [card.display_name, _detail_text(card.description, card.effects)]
		button.preview_budget = budget_text
		button.preview_political = political_text
		for id in costs["sources"]:
			button.tooltip_text += "\n★ " + controller.statuses[id].display_name + "减免"
		button.custom_minimum_size = Vector2(CardFace.WIDTH, CardFace.HEIGHT)
		button.add_theme_font_size_override("font_size", 13)
		button.theme_type_variation = "CardButton"
		button.disabled = _hand_card_disabled(costs)
		CardFace.style(button, card.rarity, not button.disabled)
		button.pressed.connect(func() -> void: _play_card_from_hand(card_id, button))
		_hand_box.add_child(button)
		var margin := CardFace.fill(button, card, _labels(), budget_text, political_text, {"sources": sources})
		margin.get_node("ContentMargin").modulate.a = 0.55 if button.disabled else 1.0
		button.enable_lift(margin)
		button.minimum_size_changed.connect(_layout_hand_height)
	_layout_hand_height()


func _layout_hand_height() -> void:
	if not is_instance_valid(_hand_box) or not is_instance_valid(_hand_scroll):
		return
	var tallest := 0.0
	for child in _hand_box.get_children():
		if child is CardButton:
			tallest = maxf(tallest, child.get_combined_minimum_size().y)
	# Long descriptions should not clip every card's bottom merely because one
	# reform needs a few extra lines. Retain scrolling for truly oversized text.
	_hand_scroll.custom_minimum_size.y = minf(maxf(310, tallest + 28), maxf(310, get_viewport_rect().size.y * 0.4))


func _hand_content_signature() -> String:
	var parts := PackedStringArray([
		str(_state.run_status),
		"busy" if _busy() else "ready",
		str(_state.budget),
		str(_state.political_capital),
	])
	for card_id in _state.hand:
		var card: CardDef = controller.cards.get(card_id)
		if card == null:
			parts.append("%s:missing" % card_id)
			continue
		var costs := controller.simulation.card_costs(card_id)
		parts.append("%s|%s|%s|%s|%s" % [
			card_id,
			str(costs["budget"]),
			str(costs["political"]),
			var_to_str(costs["sources"]),
			str(_hand_card_disabled(costs)),
		])
	return "\n".join(parts)


func _hand_card_disabled(costs: Dictionary) -> bool:
	return _busy() or _state.run_status != GameState.RunStatus.RUNNING \
		or not costs.get("hand_requirement_met", true) \
		or not controller.simulation.can_spend_budget(int(costs["budget"])) \
		or (int(costs["political"]) > 0 and _state.political_capital < int(costs["political"]))


func _ignore_card_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_card_mouse(child)


func _render_log() -> void:
	_sync_log()
	_render_forecast()


func _sync_log() -> void:
	if _log == null:
		return
	if _log_rendered_lines > _log_lines.size():
		# A defensive reset for any caller that clears the backing array directly.
		_log.clear()
		_log_rendered_lines = 0
	var appended := false
	while _log_rendered_lines < _log_lines.size():
		if _log_rendered_lines > 0:
			_log.append_text("\n")
		_log.append_text(ImpactText.highlight_bbcode(_log_lines[_log_rendered_lines]))
		_log_rendered_lines += 1
		appended = true
	if appended and _log.is_visible_in_tree():
		_log.scroll_to_line(_log_rendered_lines - 1)


func _append_log_line(line: String) -> void:
	_sync_log()
	_log_lines.append(line)
	if _log_lines.size() > LOG_LIMIT:
		_log_lines.remove_at(0)
		if _log != null and _log_rendered_lines > 0:
			_log.remove_paragraph(0)
			_log_rendered_lines -= 1
	_sync_log()


func _clear_log() -> void:
	_log_lines.clear()
	_log_rendered_lines = 0
	if _log != null:
		_log.clear()


func _scroll_log_to_end() -> void:
	if _log == null or _log_rendered_lines == 0:
		return
	_log.scroll_to_line(_log_rendered_lines - 1)


func _render_forecast() -> void:
	if _forecast == null or not _game_page.visible:
		return
	var signature := _forecast_state_signature()
	if not _forecast_dirty and signature == _forecast_signature:
		return
	_forecast.text = EconomyForecast.text(controller.simulation, _labels(), false)
	ImpactText.configure(_parameters)
	_parameters.text = ImpactText.highlight_bbcode("[b]结算公式[/b]\n%s\n\n%s" % [EconomyForecast.formulas(controller.simulation), EconomyForecast.parameters(controller.simulation, _labels())])
	_forecast_signature = signature
	_forecast_dirty = false
	_forecast_build_count += 1


func _forecast_state_signature() -> String:
	var sim := controller.simulation
	var parts := PackedStringArray([
		"%d|%d|%d|%d|%d|%d|%d|%d|%s" % [
			_state.turn, _state.turn_in_year, _state.year, _state.budget,
			_state.political_capital, _state.run_status, _state.cards_played_this_turn,
			_state.investments_played_this_turn, str(_state.base_budget_retention),
		],
		str(_state.phase),
		str(_state.base_annual_income),
		String(_state.scenario_id),
		str(_state.seed_value),
		String(_state.pending_event),
		var_to_str(_state.pending_event_choices),
		var_to_str(_state.indicators),
		var_to_str(_state.prev_indicators),
		var_to_str(_state.deck),
		var_to_str(_state.hand),
		var_to_str(_state.discard),
		var_to_str(_state.played_cards_this_turn),
		var_to_str(_state.flags),
		var_to_str(sim.economy.indicator_ids),
		var_to_str(sim.economy.derived_ids),
		var_to_str(sim.economy.bounds),
		var_to_str(sim.economy.equations.keys()),
		var_to_str(sim.economy.base_coefficients),
		var_to_str(sim.economy.scenario_coefficients),
		var_to_str(sim.rules),
		str(sim.turns.phase),
		str(sim.rng.snapshot().next_int(1_000_000_000)),
	])
	for modifier in _state.modifiers:
		parts.append("%s|%s|%d|%s|%d|%s|%d|%s|%d|%s" % [
			modifier.scope, modifier.target, modifier.op, str(modifier.value),
			modifier.remaining_turns, modifier.source, modifier.stacks, modifier.rule, modifier.ready_turn, var_to_str(modifier.data),
		])
	for cabinet in _state.cabinets:
		parts.append(String(cabinet.id))
	for entry in _state.aids:
		var definition: AidDef = entry["def"]
		parts.append("%s:%d" % [definition.id, int(entry["uses"])])
	for group in _state.pending_rewards:
		parts.append(str(group.get("type", "")))
		for option in group.get("options", []):
			var reward: Reward = option
			parts.append("%d:%s:%s" % [reward.type, reward.id, reward.label])
	return "\n".join(parts)


func _is_annual_meeting() -> bool:
	return _state != null and _state.run_status == GameState.RunStatus.RUNNING \
		and _state.pending_event == &"" and not _state.pending_rewards.is_empty() \
		and not _state.pending_rewards[0].has("event") \
		and not _state.pending_rewards[0].get("turn_reward", false) \
		and not _state.flags.get("pending_retain", false) and not _state.flags.get("pending_review", false) \
		and _state.flags.get("pending_discard_draw", []).is_empty()


func _reward_container() -> VBoxContainer:
	return _meeting_page.content if _is_annual_meeting() else _overlay_box


func _render_overlay() -> void:
	if _is_annual_meeting():
		_overlay_root.visible = false
	var variation: StringName = &"EventPanel" if _state.pending_event != &"" and _state.run_status == GameState.RunStatus.RUNNING else &""
	if _overlay_panel.theme_type_variation != variation:
		_overlay_panel.theme_type_variation = variation
	var signature := _overlay_content_signature()
	if signature == _overlay_signature:
		return
	_overlay_signature = signature
	_clear(_overlay_box)
	_clear(_meeting_page.content)
	if _state.run_status != GameState.RunStatus.RUNNING:
		_show_result()
		return
	if not _state.flags.get("pending_discard_draw", []).is_empty():
		_show_hand_choice(false, true)
		return
	if _state.flags.get("pending_retain", false):
		_show_hand_choice(true)
		return
	if _state.flags.get("pending_review", false):
		_show_hand_choice(false)
		return
	if _state.pending_event != &"":
		_show_event()
		return
	if not _state.pending_rewards.is_empty():
		_show_rewards()
		return
	_reward_group_index = -1
	_overlay_root.visible = false


func _overlay_content_signature() -> String:
	if _state.run_status != GameState.RunStatus.RUNNING:
		return "result:%d|%d|%s|%s|%d|%s" % [
			_state.run_status, _state.year, str(_state.flags.get("loss_reason", "")),
			_indicator_summary(), _state.seed_value, str(_state.turn),
		]
	if not _state.flags.get("pending_discard_draw", []).is_empty():
		return "discard:%s:%s" % [var_to_str(_state.hand), var_to_str(_state.flags["pending_discard_draw"])]
	if _state.flags.get("pending_retain", false):
		return "retain:%s" % var_to_str(_state.hand)
	if _state.flags.get("pending_review", false):
		return "review:%s" % var_to_str(_state.hand)
	if _state.pending_event != &"":
		var event_parts := PackedStringArray(["event", String(_state.pending_event), str(_state.pending_event_choices.size())])
		for index in range(_state.pending_event_choices.size()):
			var choice: Dictionary = _state.pending_event_choices[index]
			event_parts.append("%s|%s|%s" % [
				str(choice.get("label", "")),
				str(choice.get("description", "")),
				str(controller.simulation.event_choice_available(index)),
			])
		return "\n".join(event_parts)
	if not _state.pending_rewards.is_empty():
		var reward_parts := PackedStringArray(["rewards", str(_reward_group_index)])
		reward_parts.append("at:%d:%d:%d" % [_state.year, _state.turn, _state.turn_in_year])
		reward_parts.append("odds:%s:%s:%s" % [
			TextFormatter.fmt(controller.simulation.rarity_weight(&"common")),
			TextFormatter.fmt(controller.simulation.rarity_weight(&"rare")),
			TextFormatter.fmt(controller.simulation.rarity_weight(&"legendary")),
		])
		for group in _state.pending_rewards:
			reward_parts.append("%s|%s|%s" % [str(group.get("type", "")), str(group.get("token", "")), str(group.get("removal_pending", false))])
			if group.get("removal_pending", false):
				reward_parts.append(var_to_str(controller.simulation.removable_cards()))
			for option in group.get("options", []):
				var reward: Reward = option
				reward_parts.append("%d:%s:%s" % [reward.type, reward.id, reward.label])
		return "\n".join(reward_parts)
	return "none"


func _show_hand_choice(retain: bool, discard_draw: bool = false) -> void:
	var title := "选择一张手牌保留到下回合" if retain else "弃掉一张手牌，再抽两张牌"
	if discard_draw:
		var request: Dictionary = _state.flags["pending_discard_draw"][0]
		title = "弃掉一张手牌，再抽%d张牌" % int(request.get("draw_count", 2))
	_overlay_box.add_child(_label(title))
	for index in _state.hand.size():
		var card: CardDef = controller.cards.get(_state.hand[index])
		if card == null:
			continue
		var button := ImpactButton.new()
		button.text = card.display_name
		button.tooltip_text = TextFormatter.effects_text(_labels(), card.effects)
		var hand_index := index
		button.pressed.connect(func() -> void:
			if discard_draw:
				_dispatch(Command.choose_discard_card(hand_index))
			else:
				_dispatch(Command.choose_retained_card(hand_index) if retain else Command.choose_review_card(hand_index))
		)
		_overlay_box.add_child(button)
	if discard_draw:
		_overlay_root.visible = true
		return
	var skip := Button.new()
	skip.text = "不保留" if retain else "跳过"
	skip.pressed.connect(func() -> void:
		_dispatch(Command.choose_retained_card(-1) if retain else Command.choose_review_card(-1))
	)
	_overlay_box.add_child(skip)
	_overlay_root.visible = true


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
			_overlay_box.add_child(_wrapped(TextFormatter.effects_text(_labels(), controller.simulation.event_effects(definition.effects)), UiTheme.TEXT, 460.0))
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
			if StringName(choice.get("recovery_route", "")) != &"" and str(choice.get("description", "")) != "":
				text += "\n" + str(choice["description"])
			if definition != null and index < definition.choices.size() and not definition.choices[index].effects.is_empty():
				text += "\n" + TextFormatter.effects_text(_labels(), controller.simulation.event_effects(definition.choices[index].effects))
			button.text = text
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.disabled = not controller.simulation.event_choice_available(index)
			if button.disabled:
				button.tooltip_text = "预算不足"
			ImpactText.on_button(button, text, UiTheme.TEXT)
			var choice_index := index
			button.pressed.connect(func() -> void: _dispatch(Command.resolve_event(choice_index)))
			_overlay_box.add_child(button)
	_overlay_root.visible = true


func _show_rewards() -> void:
	for index in _state.pending_rewards.size():
		if _state.pending_rewards[index].get("removal_pending", false):
			_show_card_removal(index)
			return
	if _state.pending_rewards[0].has("event") or _state.pending_rewards[0].get("turn_reward", false):
		_reward_group_index = 0
		_show_reward_options(0)
		return
	if _reward_group_index >= _state.pending_rewards.size():
		_reward_group_index = -1
	if _reward_group_index >= 0:
		_show_reward_options(_reward_group_index)
		return
	var box := _reward_container()
	var odds := _wrapped("卡牌／内阁出现权重  普通 %s · 稀有 %s · 传奇 %s" % [TextFormatter.fmt(controller.simulation.rarity_weight(&"common")), TextFormatter.fmt(controller.simulation.rarity_weight(&"rare")), TextFormatter.fmt(controller.simulation.rarity_weight(&"legendary"))], UiTheme.MUTED, 460.0)
	box.add_child(odds)
	var card_number := 0
	for group_index in range(_state.pending_rewards.size()):
		var group: Dictionary = _state.pending_rewards[group_index]
		var button := Button.new()
		match int(group.get("type", -1)):
			Reward.Type.CARD:
				card_number += 1
				button.text = "领取卡牌奖励 %d" % card_number
			Reward.Type.AID:
				button.text = "领取援助奖励"
			_:
				button.text = "任命内阁"
		button.custom_minimum_size.y = 44
		var index := group_index
		button.pressed.connect(func() -> void:
			_reward_group_index = index
			_overlay_signature = UNSET_SIGNATURE
			_render_overlay()
		)
		box.add_child(button)
	var next := Button.new()
	next.text = "继续"
	next.theme_type_variation = "PrimaryButton"
	next.pressed.connect(_continue_meeting)
	box.add_child(next)
	_overlay_root.visible = not _is_annual_meeting()


func _continue_meeting() -> void:
	for index in _state.pending_rewards.size():
		var group: Dictionary = _state.pending_rewards[index]
		if int(group.get("type", -1)) == Reward.Type.CARD:
			_claim_reward(index, -1, str(group.get("token", "")))
			return
	_dispatch(Command.choose_reward([]))


func _show_card_removal(group_index: int) -> void:
	var group: Dictionary = _state.pending_rewards[group_index]
	var token := str(group.get("token", ""))
	var box := _reward_container()
	box.add_child(_label("删除一张牌"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 16)
	box.add_child(grid)
	var cards := controller.simulation.removable_cards()
	cards.sort()
	for card_id in cards:
		var card: CardDef = controller.cards[card_id]
		var button := CardButton.new()
		button.preview_card = card
		button.preview_labels = _labels()
		button.preview_enabled = false
		button.custom_minimum_size = Vector2(CardFace.WIDTH, CardFace.HEIGHT)
		CardFace.style(button, card.rarity)
		grid.add_child(button)
		CardFace.fill(button, card, _labels(), str(card.cost), str(card.political_cost))
		var id: StringName = card_id
		button.pressed.connect(func() -> void:
			_dispatch(Command.choose_removed_card(group_index, token, id))
		)
	var skip := Button.new()
	skip.text = "不删牌"
	skip.pressed.connect(func() -> void:
		_dispatch(Command.choose_removed_card(group_index, token))
	)
	box.add_child(skip)
	_overlay_root.visible = not _is_annual_meeting()


func _show_reward_options(group_index: int) -> void:
	var group: Dictionary = _state.pending_rewards[group_index]
	var token := str(group.get("token", ""))
	var box := _reward_container()
	box.add_child(_label(str(group.get("title", TYPE_LABELS.get(group.get("type"), "奖励")))))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var options: Array = group.get("options", [])
	if options.is_empty() and group.get("turn_reward", false):
		box.add_child(_wrapped("援助容量已满" if int(group.get("type", -1)) == Reward.Type.AID and controller.simulation.aid_count() >= controller.simulation.aid_capacity() else "暂无可领取的奖励", UiTheme.MUTED, 460.0))
	for option_index in options.size():
		var reward: Reward = options[option_index]
		var pick := option_index
		if reward.type == Reward.Type.CABINET:
			var cabinet: CabinetDef = controller.cabinets.get(reward.id)
			if cabinet == null:
				continue
			var column := VBoxContainer.new()
			row.add_child(column)
			var portrait := CabinetPortrait.new()
			portrait.setup(cabinet, _labels())
			portrait.pressed.connect(func() -> void: _claim_reward(group_index, pick, token))
			column.add_child(portrait)
			var appoint := ImpactButton.new()
			appoint.text = cabinet.display_name
			appoint.tooltip_text = _reward_detail(reward)
			appoint.pressed.connect(func() -> void: _claim_reward(group_index, pick, token))
			column.add_child(appoint)
			continue
		var card: CardDef = controller.cards.get(reward.id) if reward.type == Reward.Type.CARD else CardFace.aid_card(controller.aids[reward.id], controller.simulation.aid_gain_amount(reward.id))
		if card == null:
			continue
		var button := CardButton.new()
		button.preview_card = card
		button.preview_labels = _labels()
		button.preview_budget = str(card.cost)
		button.preview_political = str(card.political_cost)
		button.preview_aid = reward.type == Reward.Type.AID
		button.preview_enabled = false
		button.custom_minimum_size = Vector2(CardFace.WIDTH, CardFace.HEIGHT)
		button.disabled = not controller.simulation.reward_option_available(group, reward)
		button.tooltip_text = ""
		CardFace.style(button, card.rarity)
		row.add_child(button)
		var face := CardFace.fill(button, card, _labels(), str(card.cost), str(card.political_cost), {"aid": reward.type == Reward.Type.AID})
		button.enable_lift(face)
		button.pressed.connect(func() -> void: _claim_reward(group_index, pick, token))
	if not group.has("event") and not group.get("turn_reward", false):
		var back := Button.new()
		back.text = "返回"
		back.pressed.connect(func() -> void:
			_reward_group_index = -1
			_overlay_signature = UNSET_SIGNATURE
			_render_overlay()
		)
		box.add_child(back)
	var skip := Button.new()
	skip.text = "放弃奖励" if group.get("turn_reward", false) else "跳过"
	skip.pressed.connect(func() -> void: _claim_reward(group_index, -1, token))
	box.add_child(skip)
	_overlay_root.visible = not _is_annual_meeting()


func _claim_reward(group_index: int, option_index: int, token: String) -> void:
	if group_index < 0 or group_index >= _state.pending_rewards.size():
		return
	_reward_group_index = -1
	_dispatch(Command.claim_reward(group_index, option_index, token))


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
	_overlay_box.add_child(_label("总回合：%d" % _state.turn))
	var back := Button.new()
	back.text = "返回菜单"
	back.custom_minimum_size = Vector2(0, 36)
	back.theme_type_variation = "PrimaryButton"
	back.pressed.connect(func() -> void: exit_requested.emit())
	_overlay_box.add_child(back)
	_overlay_root.visible = true


func _dispatch(command: Command) -> void:
	if _settlement_active:
		return
	var before: GameState
	if command.kind in [Command.Kind.END_TURN, Command.Kind.CHOOSE_RETAINED_CARD]:
		before = controller.simulation.state.snapshot()
	_apply_command_events(controller.dispatch(command), before)


func _apply_command_events(events: Array, before: GameState = null) -> void:
	if before != null:
		for event: Event in events:
			if event.kind == Event.Kind.TURN_ENDED:
				_animate_turn_settlement(events, before)
				return
	_play_events(events)
	_forecast_dirty = true
	_render()
	_queue_automatic_flights(events)
	_pending_effect_feedback.append_array(EffectFeedback.cues(events, controller.simulation, _labels()))
	if not _flight_active:
		_flush_effect_feedback()


func _animate_turn_settlement(events: Array, before: GameState) -> void:
	_settlement_active = true
	var epoch := _presentation_generation
	_pending_effect_feedback.clear()
	_effect_feedback.clear()
	_overlay_root.hide()
	_end_turn_button.disabled = true
	_end_turn_button.text = "结算中…"
	var settled := TurnSettlement.settled_state(before, events, controller.simulation)
	var changes: Array[Dictionary] = []
	for row in _indicator_rows:
		var id: StringName = row["id"]
		var old_value := controller.simulation.economy.value(before, id)
		var new_value := controller.simulation.economy.value(settled, id)
		if is_equal_approx(old_value, new_value):
			continue
		changes.append({"id": id, "name": TextFormatter.indicator(_labels(), id), "label": row["label"],
			"from": old_value, "to": new_value, "color": EconomyForecast.change_color(controller.simulation, id, old_value, new_value)})
	await _turn_settlement.play(changes, _forecast.get_global_rect())
	if not is_inside_tree() or epoch != _presentation_generation:
		return
	SfxAudio.play(self, &"turn_settle")
	# Clear the completed turn before showing any reward/event/meeting or new hand.
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_played_table, "modulate:a", 0.0, 0.18)
	fade.tween_property(_hand_box, "modulate:a", 0.0, 0.18)
	await fade.finished
	if not is_inside_tree() or epoch != _presentation_generation:
		return
	_cleared_turn = before.turn
	_played_table.render([], controller.cards, _labels())
	_clear(_hand_box)
	_played_table.modulate.a = 1.0
	_hand_box.modulate.a = 1.0
	_hand_signature = UNSET_SIGNATURE
	await get_tree().process_frame
	if not is_inside_tree() or epoch != _presentation_generation:
		return
	_settlement_active = false
	_turn_settlement.clear()
	_end_turn_button.text = "结束回合"
	_apply_command_events(events)


func _flush_effect_feedback(origin: Dictionary = {}, source_id: StringName = &"") -> void:
	var pending := _pending_effect_feedback.duplicate()
	_pending_effect_feedback.clear()
	var generation := _effect_feedback.generation
	# Newly added badges and their scroll containers need their final geometry.
	for frame in 3:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if not is_instance_valid(_effect_feedback) or generation != _effect_feedback.generation:
			return
	for index in pending.size():
		var cue: Dictionary = pending[index]
		if int(cue["turn"]) != _state.turn or _is_annual_meeting():
			continue
		var target := _effect_feedback_target(str(cue["key"]), bool(cue.get("modifier", false)))
		if target == null:
			continue
		var source := origin if cue["card_id"] == source_id else EffectFeedback.capture(_find_played_card(cue["card_id"], int(cue["play_order"])))
		_effect_feedback.fly(cue, source, target, index * 0.08)


func _effect_feedback_target(key: String, modifier: bool = false) -> Control:
	if not modifier and key.begins_with("indicator:"):
		for row in _indicator_rows:
			if key == "indicator:%s" % row["id"]:
				return row["label"]
	if is_instance_valid(_effect_icons):
		for badge in _effect_icons.get_children():
			if str(badge.get_meta("effect_key", "")) == key:
				# Keep the destination inside the visible modifier strip.
				return badge if _effect_icons.get_parent().get_global_rect().encloses(badge.get_global_rect()) else _statuses_box
	return _statuses_box if modifier or not key.begins_with("indicator:") else null


func _queue_automatic_flights(events: Array) -> void:
	for event: Event in events:
		if event.kind != Event.Kind.CARD_PLAYED or not event.params.get("automatic", false) \
			or int(event.params.get("turn", -1)) != _state.turn:
			continue
		var entry := event.params.duplicate()
		var target := _find_played_card(StringName(entry["card_id"]), int(entry["play_order"]))
		if target == null:
			continue
		target.hide()
		_automatic_flights.append(entry)
	if not _flight_active:
		_start_next_automatic_flight()


func _start_next_automatic_flight() -> void:
	while not _automatic_flights.is_empty():
		var entry: Dictionary = _automatic_flights.pop_front()
		var card_id := StringName(entry["card_id"])
		var order := int(entry["play_order"])
		if int(entry["turn"]) != _state.turn or _find_played_card(card_id, order) == null:
			continue
		var card: CardDef = controller.cards.get(card_id)
		if card == null:
			continue
		var button := CardButton.new()
		button.preview_card = card
		button.preview_enabled = false
		CardFace.style(button, card.rarity)
		_flight_layer.add_child(button)
		CardFace.fill(button, card, _labels(), "0", "0")
		# Automatic plays originate at the far-left edge of the deck/hand area,
		# never take a real card out of the hand or create another deck copy.
		_begin_card_flight(button, Rect2(_hand_scroll.global_position, Vector2(CardFace.WIDTH, CardFace.HEIGHT)))
		SfxAudio.play(self, &"card_play")
		_flight_active = true
		_end_turn_button.disabled = true
		_animate_card_flight(card_id, order)
		return


func _play_card_from_hand(card_id: StringName, button: CardButton) -> void:
	if _settlement_active or _flight_active or not is_instance_valid(button) or button.disabled:
		return
	var origin_rect := button.visual_global_rect()
	_flight_active = true
	var events := controller.dispatch(Command.play_card(card_id))
	if not _events_played_card(events, card_id):
		# The command was rejected: no card entered the table, so nothing flies.
		_flight_active = false
		_apply_command_events(events)
		return
	_begin_card_flight(button, origin_rect)
	_apply_command_events(events)
	await _animate_card_flight(card_id)


func _events_played_card(events: Array, card_id: StringName) -> bool:
	for event in events:
		if event.kind == Event.Kind.CARD_PLAYED and StringName(event.params.get("card_id", &"")) == card_id:
			return true
	return false


func _begin_card_flight(button: CardButton, origin_rect: Rect2) -> void:
	_flight_generation += 1
	button.cancel_lift()
	var parent := button.get_parent()
	if parent != null:
		parent.remove_child(button)
	_flight_layer.add_child(button)
	button.custom_minimum_size = Vector2.ZERO
	button.size = origin_rect.size
	button.global_position = origin_rect.position
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW
	button.clip_contents = true
	_flight_card = button


func _animate_card_flight(card_id: StringName, play_order: int = 0) -> void:
	var generation := _flight_generation
	# Hide the destination right away so the table copy never shows up next to the
	# flying hand card, even for the frames spent waiting for the layout to settle.
	var target := _find_played_card(card_id, play_order)
	if target != null:
		target.visible = false
		_flight_target = target
	# Let containers, the scrollbar and CardTable's deferred reveal settle first.
	for _frame in CARD_FLIGHT_SETTLE_FRAMES:
		await get_tree().process_frame
		if generation != _flight_generation or not _flight_active or not is_instance_valid(_flight_card):
			return
	var settled := _find_played_card(card_id, play_order)
	if settled == null or not is_instance_valid(_flight_card):
		_cancel_flight(true)
		_hand_signature = UNSET_SIGNATURE
		_render()
		return
	if settled != _flight_target:
		# A render during the wait rebuilt the table; hide its fresh copy instead.
		if is_instance_valid(_flight_target):
			_flight_target.visible = true
		settled.visible = false
		_flight_target = settled
	var target_rect := settled.get_global_rect()
	var destination := target_rect.position - _flight_layer.global_position
	_flight_tween = create_tween()
	_flight_tween.set_parallel(true)
	_flight_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flight_tween.tween_property(_flight_card, "position", destination, CARD_FLIGHT_DURATION)
	_flight_tween.tween_property(_flight_card, "size", target_rect.size, CARD_FLIGHT_DURATION)
	_flight_tween.finished.connect(_on_card_flight_finished)


func _find_played_card(card_id: StringName, play_order: int = 0) -> Button:
	for index in range(_played_table._cards.size() - 1, -1, -1):
		var card: Button = _played_table._cards[index]
		if is_instance_valid(card) and StringName(card.get_meta("card_id", &"")) == card_id \
			and (play_order == 0 or int(card.get_meta("play_order", 0)) == play_order):
			return card
	return null


func _on_card_flight_finished() -> void:
	var effect_origin := EffectFeedback.capture(_flight_card)
	var source_id: StringName = _flight_card.preview_card.id if is_instance_valid(_flight_card) and _flight_card.preview_card != null else &""
	if is_instance_valid(_flight_target):
		_flight_target.visible = true
	if is_instance_valid(_flight_card):
		_flight_card.queue_free()
	_flight_tween = null
	_flight_card = null
	_flight_target = null
	_flight_active = false
	_end_turn_button.disabled = _busy() or _state.run_status != GameState.RunStatus.RUNNING
	_flush_effect_feedback(effect_origin, source_id)
	_start_next_automatic_flight()


func _cancel_flight(release_card: bool) -> void:
	_flight_generation += 1
	for entry in _automatic_flights:
		if not is_instance_valid(_played_table):
			break
		var target := _find_played_card(StringName(entry["card_id"]), int(entry["play_order"]))
		if target != null:
			target.show()
	_automatic_flights.clear()
	if _flight_tween != null and _flight_tween.is_valid():
		_flight_tween.kill()
	_flight_tween = null
	if release_card and is_instance_valid(_flight_card):
		_flight_card.queue_free()
	if is_instance_valid(_flight_target):
		_flight_target.visible = true
	_flight_card = null
	_flight_target = null
	_flight_active = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _flight_tween != null and _flight_tween.is_valid():
			_flight_tween.kill()
		_flight_tween = null


func _play_events(events: Array) -> void:
	SfxAudio.play_events(self, events)
	var restart := false
	for event in events:
		if event.kind in [Event.Kind.RUN_STARTED, Event.Kind.TURN_STARTED, Event.Kind.TURN_ENDED]:
			_pending_effect_feedback.clear()
			if is_instance_valid(_effect_feedback):
				_effect_feedback.clear()
		if event.kind == Event.Kind.RUN_STARTED:
			restart = true
			break
	if restart:
		_clear_log()
		_reward_group_index = -1
		_reset_section_signatures()
	for event in events:
		var line := _describe(event)
		if line != "":
			_append_log_line(line)


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
		Event.Kind.CARD_PLAYED, Event.Kind.CARD_REPLAYED:
			if params.get("automatic", false):
				return "自动出牌（免费）：%s" % _display_name(controller.cards, params.get("card_id", &""))
			return "%s：%s" % [name, _display_name(controller.cards, params.get("card_id", &""))]
		Event.Kind.CARD_GAINED, Event.Kind.CARD_REMOVED:
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
			if params.get("weakened", false):
				return "%s：强度减半" % _modifier_event_name(params)
			return "%s：%s（%s）来源 %s" % [
				name,
				_modifier_event_name(params),
				Modifier.op_label(int(params.get("op", 0))),
				params.get("source", ""),
			]
		Event.Kind.MODIFIER_EXPIRED:
			return "%s：%s 来源 %s" % [
				name,
				_modifier_event_name(params),
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
			return "%s：%s ×%d" % [name, _display_name(controller.aids, params.get("aid", &"")), int(params.get("amount", 1))]
		Event.Kind.STATUS_GAINED, Event.Kind.STATUS_TRIGGERED:
			return "[color=#7a3fb0]%s：%s[/color]" % ["获得修正" if event.kind == Event.Kind.STATUS_GAINED else "修正触发", _display_name(controller.statuses, params.get("status", &""))]
		Event.Kind.REWARD_OFFERED:
			return name
		Event.Kind.REWARD_CHOSEN:
			return name
		Event.Kind.RUN_WON:
			return "[b][color=green]%s！[/color][/b]" % name
		Event.Kind.RUN_LOST:
			return "[b][color=red]%s：%s[/color][/b]" % [name, "任期结束" if params.get("reason", "") == "deadline" else "触发经济崩溃条件"]
	return ""


func _modifier_event_name(params: Dictionary) -> String:
	var scope := StringName(params.get("scope", "indicator"))
	var target := StringName(params.get("target", ""))
	if scope == Modifier.SCOPE_SPECIAL:
		return _display_name(controller.statuses, target) if controller.statuses.has(target) else str(params.get("source", "修正"))
	return TextFormatter.modifier_target(_labels(), scope, target)


func _busy() -> bool:
	return _settlement_active or _state.pending_event != &"" or not _state.pending_rewards.is_empty() \
		or _state.flags.get("pending_retain", false) or _state.flags.get("pending_review", false) \
		or not _state.flags.get("pending_discard_draw", []).is_empty()


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


func _wrapped(text: String, color: Color, width: float = 200.0) -> RichTextLabel:
	var label := ImpactText.create(text, color)
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _reward_detail(reward: Reward) -> String:
	match reward.type:
		Reward.Type.CARD:
			var card: CardDef = controller.cards.get(reward.id)
			if card != null:
				return _detail_text(card.description, card.effects)
		Reward.Type.CABINET:
			var cabinet: CabinetDef = controller.cabinets.get(reward.id)
			if cabinet != null:
				var parts := PackedStringArray()
				if not cabinet.modifiers.is_empty():
					parts.append(TextFormatter.effects_text(_labels(), cabinet.modifiers))
				for trigger in cabinet.triggers:
					parts.append(TextFormatter.trigger_text(_labels(), trigger))
				return "\n".join(parts)
		Reward.Type.AID:
			var aid: AidDef = controller.aids.get(reward.id)
			if aid != null:
				return TextFormatter.effects_text(_labels(), aid.effects)
	return ""


func _detail_text(description: String, effects: Array) -> String:
	var parts := PackedStringArray()
	if description != "":
		parts.append(description)
	if not effects.is_empty():
		parts.append(TextFormatter.effects_text(_labels(), effects))
	return "\n".join(parts)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
