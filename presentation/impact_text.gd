class_name ImpactText
extends RichTextLabel
## Shared styling for effect numbers. Plain model/tooltip strings stay unchanged.

const GOLD := Color("a16c00")
const NUMBER_FONT := preload("res://assets/fonts/ImpactNumbers.tres")
const NUMBER_PATTERN := "[+\\-−×]?\\d+(?:\\.\\d+)?(?:/\\d+)?[%％]?|[零一二三四五六七八九十百两]+(?=[张次层点回])"
var plain_text := ""


static func create(value: String, color: Color = UiTheme.TEXT, font_size: int = 14) -> ImpactText:
	var label := ImpactText.new()
	label.plain_text = value
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("default_color", color)
	label.add_theme_constant_override("line_separation", 3)
	configure(label, font_size)
	label.text = highlight(value)
	return label


static func configure(label: RichTextLabel, font_size: int = 14) -> void:
	label.add_theme_font_override("bold_font", NUMBER_FONT)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)


static func _regex() -> RegEx:
	var regex := RegEx.new()
	regex.compile(NUMBER_PATTERN)
	return regex


static func highlight(value: String) -> String:
	# Strings are ordinary content here, not BBCode. Preserve literal brackets.
	var result := ""
	var offset := 0
	for found in _regex().search_all(value):
		result += _escape(value.substr(offset, found.get_start() - offset))
		result += "[color=#%s][b]%s[/b][/color]" % [GOLD.to_html(false), found.get_string()]
		offset = found.get_end()
	return result + _escape(value.substr(offset))


static func highlight_bbcode(value: String) -> String:
	# Internal log/formula markup: never style digits inside a tag/color code.
	var tags := RegEx.new()
	tags.compile("\\[[^\\]]*\\]")
	var result := ""
	var offset := 0
	for tag in tags.search_all(value):
		result += highlight(value.substr(offset, tag.get_start() - offset)) + tag.get_string()
		offset = tag.get_end()
	return result + highlight(value.substr(offset))


static func _escape(value: String) -> String:
	return value.replace("[", "[lb]")


static func tooltip(value: String, width: float = 340) -> Control:
	var panel := PanelContainer.new()
	var body := create(value)
	body.custom_minimum_size.x = width
	panel.add_child(body)
	return panel


static func on_button(button: Button, value: String, color: Color = UiTheme.TEXT) -> void:
	if _regex().search(value) == null:
		return
	# Keep Button's plain text for accessibility and its established input layout.
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var body := create(value, color)
	body.modulate.a = 0.55 if button.disabled else 1.0
	margin.add_child(body)
	body.minimum_size_changed.connect(func() -> void:
		button.custom_minimum_size.y = maxf(44, body.get_combined_minimum_size().y + 24)
	)


func number_bounds(start: int, length: int) -> Rect2:
	var line := get_character_line(start)
	if line < 0:
		return Rect2()
	var begin := get_line_range(line).x
	var prefix := plain_text.substr(begin, start - begin)
	var size_px := get_theme_font_size("normal_font_size")
	var normal := get_theme_font("normal_font")
	var x := 0.0
	var offset := 0
	for token in _regex().search_all(prefix):
		x += normal.get_string_size(prefix.substr(offset, token.get_start() - offset), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		x += NUMBER_FONT.get_string_size(token.get_string(), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		offset = token.get_end()
	x += normal.get_string_size(prefix.substr(offset), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var width := NUMBER_FONT.get_string_size(plain_text.substr(start, length), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	return Rect2(Vector2(x, get_line_offset(line)), Vector2(width, get_line_height(line)))
