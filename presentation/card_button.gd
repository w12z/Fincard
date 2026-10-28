class_name CardButton
extends Button

const LIFT := 12.0
var preview_budget := "0"
var preview_political := "0"
var preview_card: CardDef
var preview_labels := {}
var preview_aid: bool = false
var preview_enabled: bool = true
var _face: Control
var _frame: Panel
var _styles := {}
var _lift_tween: Tween
var _lifted := false
var _lift_enabled := false
var _hovered := false
var _down := false


func _make_custom_tooltip(for_text: String) -> Object:
	if not preview_enabled:
		return null
	return CardPreview.build(for_text, preview_budget, preview_political, preview_card, preview_labels, preview_aid)


func _has_point(point: Vector2) -> bool:
	var extra := LIFT if _lifted else 0.0
	return Rect2(Vector2(0, -extra), size + Vector2(0, extra)).has_point(point)


func set_face_styles(styles: Dictionary) -> void:
	_styles = styles
	for state in styles:
		add_theme_stylebox_override(state, StyleBoxEmpty.new() if _frame != null else styles[state])
	_update_face()


func attach_face(face: Control) -> void:
	if _face == face:
		return
	_face = face
	_frame = face.get_node("CardFrame") as Panel
	# The Panel owns the visible frame. Only the input/layout slot stays fixed.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		if not _styles.has(state):
			_styles[state] = get_theme_stylebox(state)
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(func() -> void:
		_hovered = true
		_animate_lift(_lift_enabled and not disabled)
	)
	mouse_exited.connect(func() -> void:
		_hovered = false
		_animate_lift(false)
	)
	button_down.connect(func() -> void:
		_down = true
		_update_face()
	)
	button_up.connect(func() -> void:
		_down = false
		_update_face()
	)
	focus_entered.connect(_update_face)
	focus_exited.connect(_update_face)
	_update_face()


func enable_lift(face: Control) -> void:
	attach_face(face)
	_lift_enabled = true


func cancel_lift() -> void:
	if _lift_tween != null:
		if _lift_tween.is_valid():
			_lift_tween.kill()
		_lift_tween = null
	_lifted = false
	if _face != null:
		_face.offset_top = 0.0
		_face.offset_bottom = 0.0
		_update_face()


func visual_global_rect() -> Rect2:
	if _face != null and _face.is_inside_tree():
		return _face.get_global_rect()
	return get_global_rect()


func _animate_lift(raised: bool) -> void:
	_update_face()
	if not _lift_enabled:
		return
	_lifted = raised and not disabled
	if _lift_tween != null:
		_lift_tween.kill()
	_lift_tween = create_tween().set_parallel(true)
	_lift_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var offset := -LIFT if _lifted else 0.0
	_lift_tween.tween_property(_face, "offset_top", offset, 0.14)
	_lift_tween.tween_property(_face, "offset_bottom", offset, 0.14)


func _draw() -> void:
	_update_face()


func _update_face() -> void:
	if not is_instance_valid(_frame) or _styles.is_empty():
		return
	var state := "disabled" if disabled else ("pressed" if _down or is_pressed() else ("hover" if _hovered else ("focus" if has_focus() else "normal")))
	var style: StyleBox = _styles.get(state, _styles.get("normal"))
	if style != null and _frame.get_theme_stylebox("panel") != style:
		_frame.add_theme_stylebox_override("panel", style)
