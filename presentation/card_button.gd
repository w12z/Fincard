class_name CardButton
extends Button

const LIFT := 12.0
var preview_budget := "0"
var preview_political := "0"
var preview_card: CardDef
var preview_labels := {}
var _face: Control
var _styles := {}
var _lift_tween: Tween
var _lifted := false


func _make_custom_tooltip(for_text: String) -> Object:
	return CardPreview.build(for_text, preview_budget, preview_political, preview_card, preview_labels)


func _has_point(point: Vector2) -> bool:
	var extra := LIFT if _lifted else 0.0
	return Rect2(Vector2(0, -extra), size + Vector2(0, extra)).has_point(point)


func enable_lift(face: Control) -> void:
	_face = face
	# Keep the hit rectangle in its layout slot; only the painted card moves.
	# This also avoids hover jitter along the bottom edge of the raised card.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		_styles[state] = get_theme_stylebox(state)
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_face.draw.connect(_draw_face)
	mouse_entered.connect(func() -> void: _animate_lift(not disabled))
	mouse_exited.connect(func() -> void: _animate_lift(false))
	button_down.connect(func() -> void: _face.queue_redraw())
	button_up.connect(func() -> void: _face.queue_redraw())
	focus_entered.connect(func() -> void: _face.queue_redraw())
	focus_exited.connect(func() -> void: _face.queue_redraw())


func cancel_lift() -> void:
	if _lift_tween != null:
		if _lift_tween.is_valid():
			_lift_tween.kill()
		_lift_tween = null
	_lifted = false
	if _face != null:
		_face.offset_top = 0.0
		_face.offset_bottom = 0.0
		_face.queue_redraw()


func visual_global_rect() -> Rect2:
	if _face != null and _face.is_inside_tree():
		return _face.get_global_rect()
	return get_global_rect()


func _animate_lift(raised: bool) -> void:
	_lifted = raised and not disabled
	if _lift_tween != null:
		_lift_tween.kill()
	_lift_tween = create_tween().set_parallel(true)
	_lift_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var offset := -LIFT if _lifted else 0.0
	_lift_tween.tween_property(_face, "offset_top", offset, 0.14)
	_lift_tween.tween_property(_face, "offset_bottom", offset, 0.14)
	_face.queue_redraw()


func _draw_face() -> void:
	var state := "disabled" if disabled else ("pressed" if is_pressed() else ("hover" if _lifted else "normal"))
	var rect := Rect2(Vector2.ZERO, _face.size)
	_styles[state].draw(_face.get_canvas_item(), rect)
	if has_focus():
		_styles["focus"].draw(_face.get_canvas_item(), rect)
