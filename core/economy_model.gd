class_name EconomyModel
extends RefCounted

var indicator_ids: Array[StringName] = []
var derived_ids: Array[StringName] = []
var equations: Dictionary = {}
var derived: Dictionary = {}
var bounds: Dictionary = {}


func register_indicator(id: StringName) -> void:
	if not indicator_ids.has(id):
		indicator_ids.append(id)


func register_derived(id: StringName, compute: Callable) -> void:
	derived[id] = compute
	if not derived_ids.has(id):
		derived_ids.append(id)


func set_bounds(id: StringName, min_value: float, max_value: float) -> void:
	bounds[id] = [min_value, max_value]


func clamp_indicator(state: GameState, id: StringName) -> void:
	var pair: Array = bounds.get(id, [])
	if pair.is_empty():
		return
	var raw := float(state.indicators.get(id, 0.0))
	var clamped := clampf(raw, float(pair[0]), float(pair[1]))
	if not is_equal_approx(raw, clamped):
		state.indicators[id] = clamped


func tick(state: GameState, rng: Rng) -> Array[Event]:
	var events: Array[Event] = []
	state.prev_indicators = state.indicators.duplicate()
	var deltas: Dictionary = {}
	for id in indicator_ids:
		if not equations.has(id):
			continue
		deltas[id] = float(equations[id].call(state, self, rng))
	for id in deltas:
		var delta: float = deltas[id]
		if delta == 0.0:
			continue
		_change(state, id, delta, events)
	for id in derived_ids:
		var previous := float(state.indicators.get(id, 0.0))
		var computed := float(derived[id].call(state, self))
		if is_equal_approx(previous, computed):
			continue
		state.indicators[id] = computed
		events.append(Event.new(Event.Kind.INDICATOR_CHANGED, {
			"indicator": id,
			"previous": previous,
			"current": computed,
			"delta": computed - previous,
			"derived": true,
		}))
	return events


func value(state: GameState, id: StringName) -> float:
	var result := float(state.indicators.get(id, 0.0))
	for modifier in state.modifiers:
		if modifier.target != id:
			continue
		match modifier.op:
			Modifier.Op.ADD:
				result += modifier.value
			Modifier.Op.MUL:
				result *= modifier.value
			Modifier.Op.OVERRIDE:
				result = modifier.value
	return result


func _change(state: GameState, id: StringName, delta: float, events: Array[Event]) -> void:
	var previous := float(state.indicators.get(id, 0.0))
	var current := previous + delta
	var pair: Array = bounds.get(id, [])
	if not pair.is_empty():
		current = clampf(current, float(pair[0]), float(pair[1]))
		delta = current - previous
		if delta == 0.0:
			return
	state.indicators[id] = current
	events.append(Event.new(Event.Kind.INDICATOR_CHANGED, {
		"indicator": id,
		"previous": previous,
		"current": current,
		"delta": delta,
	}))
