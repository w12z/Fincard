class_name CardPileView
extends VBoxContainer

var _count: Label
var _back: Panel
var draw_pile := false


func setup(is_draw_pile: bool) -> void:
	draw_pile = is_draw_pile
	name = "DrawPile" if draw_pile else "DiscardPile"
	custom_minimum_size.x = 78
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = Panel.new()
	_back.custom_minimum_size = Vector2(70, 98)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("eaf1fc") if draw_pile else Color("f2eee7")
	style.border_color = UiTheme.ACCENT_DARK if draw_pile else UiTheme.MUTED
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.12)
	style.shadow_size = 3
	style.shadow_offset = Vector2(3, 3)
	_back.add_theme_stylebox_override("panel", style)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	var mark := Label.new()
	mark.text = "FIN\nCARD" if draw_pile else "弃牌"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.add_theme_color_override("font_color", style.border_color)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(mark)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	set_count(0)


func set_count(count: int) -> void:
	_count.text = "%s %d" % ["牌库" if draw_pile else "弃牌", count]
	_back.modulate.a = 0.45 if count == 0 else 1.0


func card_rect() -> Rect2:
	return _back.get_global_rect()
