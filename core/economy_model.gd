class_name EconomyModel
extends RefCounted

var indicator_ids: Array[StringName] = []
var derived_ids: Array[StringName] = []
var equations: Dictionary = {}
var derived: Dictionary = {}
var bounds: Dictionary = {}
var base_bounds: Dictionary = {}
var base_coefficients: Dictionary = {}
var scenario_coefficients: Dictionary = {}


func set_scenario_coefficients(overrides: Dictionary) -> void:
	scenario_coefficients = overrides


func coefficient(state: GameState, key: StringName) -> float:
	var value := float(base_coefficients.get(key, 0.0))
	if scenario_coefficients.has(key):
		value = float(scenario_coefficients[key])
	for modifier in state.modifiers:
		if modifier.scope != Modifier.SCOPE_COEFFICIENT or modifier.target != key:
			continue
		match modifier.op:
			Modifier.Op.ADD:
				value += modifier.value
			Modifier.Op.MUL:
				value *= modifier.value
			Modifier.Op.OVERRIDE:
				value = modifier.value
	return value


func register_indicator(id: StringName) -> void:
	if not indicator_ids.has(id):
		indicator_ids.append(id)


func register_derived(id: StringName, compute: Callable) -> void:
	derived[id] = compute
	if not derived_ids.has(id):
		derived_ids.append(id)


func set_bounds(id: StringName, min_value: float, max_value: float) -> void:
	bounds[id] = [min_value, max_value]


func reset_bounds() -> void:
	bounds.clear()
	for key in base_bounds:
		bounds[key] = base_bounds[key]


func apply_bounds_overrides(overrides: Dictionary) -> void:
	for key in overrides:
		var pair = overrides[key]
		if pair is Array and pair.size() == 2:
			bounds[key] = [float(pair[0]), float(pair[1])]
		elif pair == null:
			bounds.erase(key)


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
		if modifier.scope != Modifier.SCOPE_INDICATOR or modifier.target != id:
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
