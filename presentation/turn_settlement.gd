class_name TurnSettlement
extends Control
## Visual staging only. Values come from actual resolved events, never a second tick.

signal indicator_settled(id: StringName)

const FLIGHT_SECONDS := 0.20
const COUNT_SECONDS := 0.12
const STEP_PAUSE := 0.05
var generation := 0
var _tweens: Array[Tween] = []
var _highlighted: Label
var _original_color := Color.WHITE


func _init() -> void:
	name = "TurnSettlement"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func clear() -> void:
	generation += 1
	if is_instance_valid(_highlighted):
		_highlighted.add_theme_color_override("font_color", _original_color)
	_highlighted = null
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	hide()


func play(changes: Array[Dictionary], forecast_rect: Rect2) -> void:
	clear()
	var epoch := generation
	show()
	for index in changes.size():
		var change: Dictionary = changes[index]
		var target: Label = change["label"]
		if not is_instance_valid(target) or is_equal_approx(float(change["from"]), float(change["to"])):
			continue
		var number := Label.new()
		number.text = TextFormatter.signed(float(change["to"]) - float(change["from"]))
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number.add_theme_font_size_override("font_size", 20)
		number.add_theme_font_override("font", ImpactText.NUMBER_FONT)
		number.add_theme_color_override("font_color", change["color"])
		number.add_theme_color_override("font_outline_color", Color.WHITE)
		number.add_theme_constant_override("outline_size", 5)
		add_child(number)
		number.set_meta("indicator", change["id"])
		number.global_position = forecast_rect.position + Vector2(95, minf(30 + index * 38, forecast_rect.size.y - 20))
		var start := number.position
		var destination := target.get_global_rect().end - global_position - Vector2(32, 16)
		var tween := create_tween()
		_tweens.append(tween)
		number.modulate.a = 0
		tween.tween_property(number, "modulate:a", 1.0, 0.04)
		tween.tween_property(number, "position", destination, FLIGHT_SECONDS).from(start).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(func() -> void:
			if not is_instance_valid(target):
				return
			_highlighted = target
			_original_color = target.get_theme_color("font_color")
			target.add_theme_color_override("font_color", change["color"])
			SfxAudio.play(self, &"effect_arrive")
		)
		tween.tween_method(func(t: float) -> void:
			if is_instance_valid(target):
				target.text = "%s：%s" % [change["name"], TextFormatter.fmt(lerpf(float(change["from"]), float(change["to"]), t))]
		, 0.0, 1.0, COUNT_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func() -> void:
			if is_instance_valid(target):
				target.text = "%s：%s" % [change["name"], TextFormatter.fmt(float(change["to"]))]
			indicator_settled.emit(StringName(change["id"]))
		)
		tween.tween_property(number, "modulate:a", 0.0, 0.08)
		tween.tween_callback(number.queue_free)
		await get_tree().create_timer(0.04 + FLIGHT_SECONDS + COUNT_SECONDS + 0.08 + STEP_PAUSE).timeout
		if not is_inside_tree() or epoch != generation:
			return
		if is_instance_valid(_highlighted):
			_highlighted.add_theme_color_override("font_color", _original_color)
		_highlighted = null
		_tweens.clear()
	if changes.is_empty():
		await get_tree().create_timer(0.2).timeout
	# Remain an input blocker until the caller finishes clearing the cards.


static func settled_state(before: GameState, events: Array, sim: Simulation) -> GameState:
	var settled := before.snapshot()
	for event: Event in events:
		if event.kind == Event.Kind.TURN_STARTED:
			break
		var params := event.params
		if event.kind == Event.Kind.INDICATOR_CHANGED:
			settled.indicators[StringName(params["indicator"])] = float(params["current"])
		elif event.kind == Event.Kind.MODIFIER_EXPIRED:
			var expired: Modifier
			for modifier in settled.modifiers.duplicate():
				if modifier.target == StringName(params.get("target", "")) and modifier.scope == StringName(params.get("scope", "")) \
					and modifier.source == StringName(params.get("source", "")):
					if expired == null or modifier.remaining_turns == 1:
						expired = modifier
					if modifier.remaining_turns == 1:
						break
			# Same-name investments can coexist with different lifetimes.
			# One expiry event must remove only one source, never every copy.
			if expired != null:
				settled.modifiers.erase(expired)
		elif event.kind == Event.Kind.MODIFIER_APPLIED:
			for modifier in sim.state.modifiers:
				if modifier.target == StringName(params.get("target", "")) and modifier.scope == StringName(params.get("scope", "")) \
					and modifier.source == StringName(params.get("source", "")):
					settled.modifiers.append(modifier.snapshot())
					break
	sim.economy.refresh_derived(settled)
	return settled
