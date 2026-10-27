class_name CabinetPortrait
extends Button

var cabinet_id: StringName
var portrait: TextureRect
var rarity: StringName
var rarity_text: String


func setup(cabinet: CabinetDef, labels: Dictionary) -> void:
	cabinet_id = cabinet.id
	rarity = cabinet.rarity
	rarity_text = "［%s］" % TextFormatter.rarity_name(labels, rarity)
	theme_type_variation = "CabinetPortrait"
	custom_minimum_size = Vector2(68, 68)
	mouse_default_cursor_shape = Control.CURSOR_HELP
	var portrait_theme := UiTheme.build()
	for state in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = portrait_theme.get_stylebox(state, "CabinetPortrait").duplicate()
		style.border_color = UiTheme.rarity_color(rarity)
		add_theme_stylebox_override(state, style)
	var lines := PackedStringArray([cabinet.display_name])
	for effect in cabinet.modifiers:
		lines.append("· " + TextFormatter.effect_text(labels, effect))
	for trigger in cabinet.triggers:
		lines.append("· " + TextFormatter.trigger_text(labels, trigger))
	tooltip_text = "\n".join(lines)
	portrait = TextureRect.new()
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 5
	portrait.offset_top = 5
	portrait.offset_right = -5
	portrait.offset_bottom = -5
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://assets/portraits/%s.png" % cabinet.id
	if ResourceLoader.exists(path):
		portrait.texture = load(path)
	add_child(portrait)


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.theme = UiTheme.build()
	panel.theme_type_variation = "CountryPanel"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var lines := for_text.split("\n", true, 1)
	var title := Label.new()
	title.text = lines[0]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
	content.add_child(title)
	var tier := Label.new()
	tier.text = rarity_text
	tier.add_theme_color_override("font_color", UiTheme.rarity_color(rarity))
	content.add_child(tier)
	if lines.size() > 1:
		var body := Label.new()
		body.text = lines[1]
		body.custom_minimum_size.x = 320
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(body)
	return panel
