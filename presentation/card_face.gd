class_name CardFace
extends RefCounted

const WIDTH := 180.0
const HEIGHT := 286.0


static func style(button: Button, rarity: StringName, playable: bool = false) -> void:
	var styles := {}
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("f1f3f6") if state == "disabled" else (Color("effaf5") if playable else Color.WHITE)
		if state in ["hover", "pressed", "hover_pressed"]:
			box.bg_color = box.bg_color.darkened(0.025)
		box.border_color = UiTheme.rarity_color(rarity)
		box.set_border_width_all(7 if state in ["hover", "focus", "pressed", "hover_pressed"] else 6)
		box.set_corner_radius_all(10)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		box.shadow_color = Color(0.03, 0.08, 0.15, 0.16)
		box.shadow_size = 4
		box.shadow_offset = Vector2(1, 3)
		styles[state] = box
	if button is CardButton:
		button.set_face_styles(styles)
	else:
		for state in styles:
			button.add_theme_stylebox_override(state, styles[state])


static func fill(button: Button, card: CardDef, labels: Dictionary, budget: String, political: String, options: Dictionary = {}) -> Control:
	var compact := bool(options.get("compact", false))
	var face := Control.new()
	face.name = "CardFace"
	button.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := Panel.new()
	frame.name = "CardFrame"
	face.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", button.get_theme_stylebox("normal"))
	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	face.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)
	if options.has("order"):
		content.add_child(_label("%02d" % int(options["order"]), UiTheme.TEXT, 22, true))
	var title := _label(card.display_name, UiTheme.card_type_color(card.card_type), 16 if compact else 13, true)
	title.name = "CardName"
	content.add_child(title)
	if not compact and not options.get("aid", false):
		var costs := HBoxContainer.new()
		costs.name = "Costs"
		costs.alignment = BoxContainer.ALIGNMENT_CENTER
		costs.add_theme_constant_override("separation", 10)
		costs.add_child(ResourceAmount.create(&"budget", budget))
		costs.add_child(ResourceAmount.create(&"political", political))
		content.add_child(costs)
	content.add_child(ArtAssets.card_picture(card.id, 54 if compact else 86))
	if not compact:
		content.add_child(_label("援助" if options.get("aid", false) else TextFormatter.card_type_name(labels, card.card_type), UiTheme.TEXT, 13, true))
		if card.once_per_run:
			content.add_child(_label("法案 · 限通过一次", UiTheme.TEXT, 13))
	var effects := _label(TextFormatter.effects_text(labels, card.effects), UiTheme.TEXT, 13)
	effects.name = "Effects"
	effects.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if compact:
		effects.max_lines_visible = 4
		effects.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(effects)
	for source in options.get("sources", []):
		content.add_child(_label("★ " + str(source) + "减免", UiTheme.TEXT, 13))
	if not compact:
		content.minimum_size_changed.connect(func() -> void:
			button.custom_minimum_size.x = maxf(WIDTH, content.get_combined_minimum_size().x + 20)
			button.custom_minimum_size.y = maxf(HEIGHT, content.get_combined_minimum_size().y + 20)
		)
	_ignore_mouse(face)
	if button is CardButton:
		button.attach_face(face)
	return face


static func aid_card(aid: AidDef, count: int = -1) -> CardDef:
	var card := CardDef.new()
	card.id = aid.id
	var quantity := aid.uses if count < 0 else count
	card.display_name = aid.display_name + (" ×%d" % quantity if quantity > 1 else "")
	card.card_type = &"investment"
	card.rarity = &"common"
	card.effects = aid.effects
	return card


static func _label(text: String, color: Color, font_size: int, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	return label


static func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)
