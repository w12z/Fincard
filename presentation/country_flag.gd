class_name CountryFlag
extends Control

# Local, deterministic heraldry: no image downloads or gameplay RNG consumption.
var country_id: StringName = &""
var _colors: Array[Color] = []
var _pattern: int = 0
var _emblem: int = 0


func setup(id: StringName) -> void:
	country_id = id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var random := RandomNumberGenerator.new()
	random.seed = String(id).hash()
	var palettes := [
		[Color("163d55"), Color("f5ebd5"), Color("d7ae60")],
		[Color("20574d"), Color("f5ecd9"), Color("d6ad61")],
		[Color("762f42"), Color("f7eedb"), Color("ddb76a")],
		[Color("263d72"), Color("f2ecdd"), Color("ce6251")],
		[Color("31554b"), Color("e0b46c"), Color("f4eddb")],
	]
	_colors.assign(palettes[random.randi_range(0, palettes.size() - 1)])
	_pattern = random.randi_range(0, 4)
	_emblem = random.randi_range(0, 1)
	queue_redraw()


func _draw() -> void:
	if _colors.is_empty():
		return
	var rect := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	draw_rect(Rect2(rect.position + Vector2(0, 3), rect.size), Color(0.06, 0.12, 0.2, 0.16))
	draw_rect(rect, _colors[0])
	var w := rect.size.x
	var h := rect.size.y
	var origin := rect.position
	match _pattern:
		0:
			draw_rect(Rect2(origin + Vector2(0, h / 3), Vector2(w, h / 3)), _colors[1])
		1:
			draw_rect(Rect2(origin + Vector2(w / 3, 0), Vector2(w / 3, h)), _colors[1])
		2:
			draw_rect(Rect2(origin + Vector2(0, h * 0.4), Vector2(w, h * 0.2)), _colors[1])
			draw_rect(Rect2(origin + Vector2(w * 0.3, 0), Vector2(w * 0.12, h)), _colors[1])
		3:
			draw_rect(Rect2(origin + Vector2(0, h * 0.5), Vector2(w, h * 0.5)), _colors[1])
			draw_rect(Rect2(origin, Vector2(w * 0.42, h * 0.5)), _colors[2])
		4:
			draw_colored_polygon(PackedVector2Array([origin, origin + Vector2(w * 0.52, h * 0.5), origin + Vector2(0, h)]), _colors[1])
	var center := origin + Vector2(w * 0.5, h * 0.5)
	var radius := h * 0.17
	draw_circle(center, radius * 1.25, _colors[0], true, -1, true)
	if _emblem == 0:
		var points := PackedVector2Array()
		for index in 10:
			var angle := -PI / 2 + index * PI / 5
			points.append(center + Vector2(cos(angle), sin(angle)) * radius * (1.0 if index % 2 == 0 else 0.43))
		draw_colored_polygon(points, _colors[2])
	else:
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.8, 0), center + Vector2(0, radius), center - Vector2(radius * 0.8, 0)]), _colors[2])
	draw_rect(rect, Color(1, 1, 1, 0.22), false, 1, true)


static func create(id: StringName, height: float) -> AspectRatioContainer:
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1.6
	aspect.custom_minimum_size = Vector2(0, height)
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flag := CountryFlag.new()
	flag.setup(id)
	aspect.add_child(flag)
	return aspect
