class_name CardTable
extends Control

const CARD_SIZE := Vector2(184, 224)
const MIN_STEP := 44.0
var _cards: Array[Button] = []
var _reveal_pending: bool = false


func _ready() -> void:
	resized.connect(_layout_cards)


func render(history: Array[StringName], definitions: Dictionary, labels: Dictionary) -> void:
	var previous_count := _cards.size()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cards.clear()
	custom_minimum_size = Vector2(0 if history.is_empty() else CARD_SIZE.x + MIN_STEP * (history.size() - 1), CARD_SIZE.y + 24)
	for index in history.size():
		var card: CardDef = definitions.get(history[index])
		if card == null:
			continue
		var color := UiTheme.card_type_color(card.card_type)
		var button := CardButton.new()
		button.preview_card = card
		button.preview_labels = labels
		button.preview_budget = str(card.cost)
		button.preview_political = str(card.political_cost)
		button.custom_minimum_size = CARD_SIZE
		button.size = CARD_SIZE
		button.clip_contents = true
		button.mouse_default_cursor_shape = Control.CURSOR_HELP
		button.add_theme_stylebox_override("normal", _style(UiTheme.CARD_BORDER, false))
		button.add_theme_stylebox_override("hover", _style(UiTheme.ACCENT, true))
		button.add_theme_stylebox_override("pressed", _style(UiTheme.ACCENT, true))
		button.set_meta("card_id", card.id)
		button.set_meta("play_order", index + 1)
		button.tooltip_text = "%d. %s［%s］\n%s\n%s" % [index + 1, card.display_name, TextFormatter.rarity_name(labels, card.rarity), card.description, TextFormatter.effects_text(labels, card.effects)]
		add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 12)
		button.add_child(margin)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		margin.add_child(content)
		content.add_child(_label("%02d" % (index + 1), 22, UiTheme.TEXT))
		var title := _label(card.display_name, 16, color)
		title.name = "CardName"
		content.add_child(title)
		var rarity := CardPreview.rarity_label(card, labels)
		rarity.add_theme_font_size_override("font_size", 12)
		content.add_child(rarity)
		content.add_child(HSeparator.new())
		var effect_label := _label(TextFormatter.effects_text(labels, card.effects), 13, UiTheme.TEXT)
		effect_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		effect_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		effect_label.max_lines_visible = 5
		content.add_child(effect_label)
		_ignore_mouse(margin)
		_cards.append(button)
		button.mouse_entered.connect(func() -> void: button.z_index = _cards.size() + 1)
		button.mouse_exited.connect(func() -> void: button.z_index = int(button.get_meta("play_order")))
	_layout_cards()
	if _cards.size() != previous_count and not _cards.is_empty() and get_parent() is ScrollContainer:
		call_deferred("_reveal_latest")


func _reveal_latest() -> void:
	if _reveal_pending:
		return
	_reveal_pending = true
	# Wait for container minimum sizes and scrollbar ranges to settle.
	await get_tree().process_frame
	await get_tree().process_frame
	_reveal_pending = false
	if not _cards.is_empty() and get_parent() is ScrollContainer:
		get_parent().ensure_control_visible(_cards.back())


func _layout_cards() -> void:
	if _cards.is_empty():
		return
	var step := minf(90, maxf(MIN_STEP, (size.x - CARD_SIZE.x) / maxf(1, _cards.size() - 1)))
	var start := maxf(0, (size.x - CARD_SIZE.x - step * (_cards.size() - 1)) / 2)
	for index in _cards.size():
		_cards[index].position = Vector2(start + index * step, 12 + (index % 3) * 3)
		_cards[index].z_index = index + 1


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _style(color: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ffffff") if hovered else Color("f3f6fa")
	style.border_color = color
	style.set_border_width_all(2 if hovered else 1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.03, 0.08, 0.15, 0.22)
	style.shadow_size = 7 if hovered else 4
	style.shadow_offset = Vector2(2, 4)
	return style


func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)
