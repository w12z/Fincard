class_name CardPileMotion
extends Control
## Temporary visual cards only; the simulation remains the sole owner of piles.

const DURATION := 0.28
const STAGGER := 0.045
var generation := 0
var _tweens: Array[Tween] = []


func _init() -> void:
	name = "CardPileMotion"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func clear() -> void:
	generation += 1
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	hide()


static func capture(button: CardButton, compact: bool = false) -> Dictionary:
	return {"card": button.preview_card, "rect": button.visual_global_rect(), "compact": compact,
		"budget": button.preview_budget, "political": button.preview_political}


func transfer(entries: Array[Dictionary], draw: bool, pile: Rect2, labels: Dictionary) -> void:
	if entries.is_empty():
		return
	var epoch := generation
	show()
	SfxAudio.play(self, &"card_play")
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var ghost := CardButton.new()
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.preview_enabled = false
		ghost.clip_contents = true
		var card: CardDef = entry["card"]
		CardFace.style(ghost, card.rarity)
		add_child(ghost)
		CardFace.fill(ghost, card, labels, str(entry.get("budget", card.cost)), str(entry.get("political", card.political_cost)), {"compact": entry.get("compact", false)})
		var rect: Rect2 = entry["rect"]
		var start := pile if draw else rect
		var end := rect if draw else pile
		ghost.set_meta("card_id", card.id)
		ghost.set_meta("direction", "draw" if draw else "discard")
		ghost.position = start.position - global_position
		ghost.size = rect.size
		ghost.scale = start.size / rect.size
		ghost.rotation = -0.08 if draw else 0.0
		var tween := create_tween()
		_tweens.append(tween)
		tween.tween_interval(mini(index, 12) * STAGGER)
		tween.set_parallel(true)
		tween.tween_property(ghost, "position", end.position - global_position, DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(ghost, "scale", end.size / rect.size, DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ghost, "rotation", 0.0 if draw else 0.08, DURATION)
		if not draw:
			tween.tween_property(ghost, "modulate:a", 0.0, 0.09).set_delay(DURATION - 0.09)
		tween.chain().tween_callback(func() -> void:
			var destination: Control = entry.get("destination")
			if is_instance_valid(destination) and destination.is_inside_tree():
				destination.modulate.a = 1.0
			ghost.queue_free()
		)
	await get_tree().create_timer(DURATION + mini(entries.size() - 1, 12) * STAGGER + 0.04).timeout
	if epoch == generation:
		for entry in entries:
			var destination: Control = entry.get("destination")
			if is_instance_valid(destination):
				destination.modulate.a = 1.0
		_tweens.clear()


func reshuffle(discard: Rect2, deck: Rect2) -> void:
	var epoch := generation
	show()
	for index in 3:
		var back := Panel.new()
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("eaf1fc")
		style.border_color = UiTheme.ACCENT_DARK
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		back.add_theme_stylebox_override("panel", style)
		add_child(back)
		back.position = discard.position - global_position + Vector2(index * 2, -index * 2)
		back.size = discard.size
		var tween := create_tween()
		_tweens.append(tween)
		tween.tween_interval(index * 0.04)
		tween.tween_property(back, "position", deck.position - global_position, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(back.queue_free)
	await get_tree().create_timer(0.38).timeout
	if epoch == generation:
		_tweens.clear()
