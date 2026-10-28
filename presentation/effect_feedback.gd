class_name EffectFeedback
extends Control
## Presentation-only copies of card numbers, driven by resolved game events.

const TRAVEL_TIME := 0.58
var generation := 0


func _init() -> void:
	name = "EffectFeedback"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func clear() -> void:
	generation += 1
	for child in get_children():
		remove_child(child)
		child.queue_free()


static func capture(card: Control) -> Dictionary:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return {}
	var result := {"fallback": card.get_global_rect().get_center(), "tokens": []}
	var effects := card.find_child("Effects", true, false)
	if effects == null:
		return result
	var plain: String = effects.plain_text if effects is ImpactText else effects.text
	var regex := RegEx.new()
	regex.compile("[+\\-×]\\d+(?:\\.\\d+)?%?")
	for found in regex.search_all(plain):
		var bounds := Rect2()
		if effects is ImpactText:
			bounds = effects.number_bounds(found.get_start(), found.get_end() - found.get_start())
		else:
			for index in range(found.get_start(), found.get_end()):
				var character: Rect2 = effects.get_character_bounds(index)
				if character.has_area():
					bounds = character if not bounds.has_area() else bounds.merge(character)
		if not bounds.has_area():
			continue
		var origin: Vector2 = effects.get_global_transform() * bounds.position
		var line_start := plain.left(found.get_start()).rfind("\n") + 1
		var line_end := plain.find("\n", found.get_end())
		if line_end < 0:
			line_end = plain.length()
		result["tokens"].append({"text": found.get_string(), "position": origin,
			"context": plain.substr(line_start, line_end - line_start),
			"font": ImpactText.NUMBER_FONT if effects is ImpactText else effects.get_theme_font("font"),
			"font_size": effects.get_theme_font_size("normal_font_size") if effects is ImpactText else effects.get_theme_font_size("font_size")})
	return result


static func cues(events: Array, sim: Simulation, labels: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var card_id: StringName = &""
	var order := 0
	for event: Event in events:
		var params := event.params
		if event.kind in [Event.Kind.TURN_STARTED, Event.Kind.TURN_ENDED]:
			card_id = &""
		if event.kind in [Event.Kind.CARD_PLAYED, Event.Kind.CARD_REPLAYED]:
			card_id = StringName(params.get("card_id", ""))
			order = int(params.get("play_order", 0))
		if card_id == &"":
			continue
		var cue := {"card_id": card_id, "play_order": order, "turn": sim.state.turn}
		if event.kind == Event.Kind.INDICATOR_CHANGED:
			var delta := float(params.get("delta", 0))
			if is_zero_approx(delta):
				continue
			var target := StringName(params["indicator"])
			cue.merge({"key": "indicator:%s" % target, "text": TextFormatter.signed(delta),
				"hint": TextFormatter.indicator(labels, target),
				"color": EconomyForecast.change_color(sim, target, float(params["previous"]), float(params["current"]))})
		elif event.kind == Event.Kind.MODIFIER_APPLIED:
			var scope := StringName(params.get("scope", "indicator"))
			var target := StringName(params.get("target", ""))
			var modifier: Modifier
			for entry in sim.state.modifiers:
				if entry.scope == scope and entry.target == target and entry.source == StringName(params.get("source", "")):
					modifier = entry
			if modifier == null:
				continue
			var number := "×1" if scope == Modifier.SCOPE_SPECIAL else TextFormatter.signed(modifier.value)
			if scope != Modifier.SCOPE_SPECIAL and modifier.op == Modifier.Op.MUL:
				number = "×" + TextFormatter.fmt(modifier.value)
			if scope != Modifier.SCOPE_SPECIAL and modifier.op == Modifier.Op.OVERRIDE:
				number = "=" + TextFormatter.fmt(modifier.value)
			cue.merge({"key": "%s:%s" % [scope, target], "text": number, "modifier": true,
				"hint": TextFormatter.modifier_target(labels, scope, target), "color": UiTheme.ACCENT})
		else:
			continue
		result.append(cue)
	return result


func fly(cue: Dictionary, origin: Dictionary, target: Control, delay: float = 0.0) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree():
		return
	var text := str(cue["text"])
	var source := {}
	for token: Dictionary in origin.get("tokens", []):
		if token["text"] == text and str(token.get("context", "")).contains(str(cue.get("hint", ""))):
			source = token
			break
	if source.is_empty():
		for token: Dictionary in origin.get("tokens", []):
			if token["text"] == text:
				source = token
				break
	var number := Label.new()
	number.text = text
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.add_theme_font_size_override("font_size", int(source.get("font_size", 16)))
	if source.has("font"):
		number.add_theme_font_override("font", source["font"])
	number.add_theme_font_override("font", ImpactText.NUMBER_FONT)
	number.add_theme_color_override("font_color", ImpactText.GOLD)
	number.add_theme_color_override("font_outline_color", Color.WHITE)
	number.add_theme_constant_override("outline_size", 4)
	number.set_meta("effect_key", cue["key"])
	add_child(number)
	number.global_position = source.get("position", origin.get("fallback", get_global_rect().get_center()))
	var start := number.position
	var end := target.get_global_rect().get_center() - global_position - number.get_combined_minimum_size() * 0.5
	var bend := (start + end) * 0.5 + Vector2(0, -60)
	number.pivot_offset = number.get_combined_minimum_size() * 0.5
	var tween := number.create_tween()
	number.modulate.a = 0.0
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(number, "modulate:a", 1.0, 0.06)
	tween.tween_method(func(t: float) -> void:
		number.position = start.lerp(bend, t).lerp(bend.lerp(end, t), t)
		number.scale = Vector2.ONE * (1.0 + sin(t * PI) * 0.65)
	, 0.0, 1.0, TRAVEL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: _pulse(target, cue["color"]))
	tween.tween_property(number, "modulate:a", 0.0, 0.12)
	tween.tween_callback(number.queue_free)


func _pulse(target: Control, color: Color) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	SfxAudio.play(self, &"effect_arrive")
	var pulse := Panel.new()
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.13)
	style.border_color = Color(color, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	pulse.add_theme_stylebox_override("panel", style)
	add_child(pulse)
	pulse.global_position = target.global_position - Vector2(5, 3)
	pulse.size = target.size + Vector2(10, 6)
	var tween := pulse.create_tween()
	tween.tween_property(pulse, "modulate:a", 0.0, 0.3)
	tween.tween_callback(pulse.queue_free)
