class_name UiTheme
extends RefCounted

const BG_TOP := Color("eaf3ff")
const BG_BOTTOM := Color("fff6e9")
const TEXT := Color("1f2a37")
const MUTED := Color("64748b")
const ACCENT := Color("2f6fed")
const ACCENT_DARK := Color("1e4fc4")
const POSITIVE := Color("1a9e6a")
const NEGATIVE := Color("e5484d")
const WARNING := Color("e08a00")
const PANEL_BG := Color("ffffff")
const PANEL_BORDER := Color("d6e4f0")
const CARD_BORDER := Color("9ec2f5")


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14

	theme.set_stylebox("panel", "PanelContainer", _panel_style(PANEL_BG, PANEL_BORDER, 12, 1, 10))
	theme.set_stylebox("panel", "Panel", _panel_style(PANEL_BG, PANEL_BORDER, 12, 1, 10))

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_constant("line_separation", "RichTextLabel", 3)

	theme.set_stylebox("normal", "Button", _button_style(Color("ffffff"), Color("c7d7ea"), 8, 12, 6))
	theme.set_stylebox("hover", "Button", _button_style(Color("eaf1fd"), ACCENT, 8, 12, 6))
	theme.set_stylebox("pressed", "Button", _button_style(Color("d7e6fb"), ACCENT_DARK, 8, 12, 6))
	theme.set_stylebox("disabled", "Button", _button_style(Color("f1f3f6"), Color("e2e8f0"), 8, 12, 6))
	theme.set_stylebox("focus", "Button", _button_style(Color("eaf1fd"), ACCENT, 8, 12, 6))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT_DARK)
	theme.set_color("font_pressed_color", "Button", ACCENT_DARK)
	theme.set_color("font_disabled_color", "Button", MUTED)

	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _button_style(ACCENT, ACCENT, 8, 16, 8))
	theme.set_stylebox("hover", "PrimaryButton", _button_style(ACCENT_DARK, ACCENT_DARK, 8, 16, 8))
	theme.set_stylebox("pressed", "PrimaryButton", _button_style(ACCENT_DARK, ACCENT_DARK, 8, 16, 8))
	theme.set_stylebox("disabled", "PrimaryButton", _button_style(Color("b9c9e6"), Color("b9c9e6"), 8, 16, 8))
	theme.set_stylebox("focus", "PrimaryButton", _button_style(ACCENT_DARK, ACCENT_DARK, 8, 16, 8))
	theme.set_color("font_color", "PrimaryButton", Color("ffffff"))
	theme.set_color("font_hover_color", "PrimaryButton", Color("ffffff"))
	theme.set_color("font_pressed_color", "PrimaryButton", Color("ffffff"))
	theme.set_color("font_disabled_color", "PrimaryButton", Color("eef3fb"))

	theme.set_type_variation("CardButton", "Button")
	theme.set_stylebox("normal", "CardButton", _button_style(Color("ffffff"), CARD_BORDER, 10, 10, 8))
	theme.set_stylebox("hover", "CardButton", _button_style(Color("eaf1fd"), ACCENT, 10, 10, 8))
	theme.set_stylebox("pressed", "CardButton", _button_style(Color("d7e6fb"), ACCENT_DARK, 10, 10, 8))
	theme.set_stylebox("disabled", "CardButton", _button_style(Color("f1f3f6"), Color("dbe3ee"), 10, 10, 8))
	theme.set_stylebox("focus", "CardButton", _button_style(Color("eaf1fd"), ACCENT, 10, 10, 8))
	theme.set_color("font_color", "CardButton", TEXT)
	theme.set_color("font_hover_color", "CardButton", ACCENT_DARK)
	theme.set_color("font_disabled_color", "CardButton", MUTED)

	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", ACCENT_DARK)
	theme.set_color("font_pressed_color", "CheckBox", ACCENT_DARK)

	return theme


static func gradient_background() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([BG_TOP, BG_BOTTOM])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 1.0)
	return texture


static func _panel_style(bg: Color, border: Color, radius: int, border_width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.shadow_color = Color(0.1, 0.2, 0.35, 0.08)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


static func _button_style(bg: Color, border: Color, radius: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style
