class_name ModifierRecency
extends RefCounted
## UI history only. Neither sorting nor highlighting alters game modifiers.

var _shapes := {}
var _changes := {}
var _pending := {}
var _serial := 0


func clear() -> void:
	_shapes.clear()
	_changes.clear()
	_pending.clear()
	_serial = 0


func record(events: Array, turn: int) -> void:
	for event: Event in events:
		if event.kind == Event.Kind.RUN_STARTED:
			clear()
		if event.kind not in [Event.Kind.MODIFIER_APPLIED, Event.Kind.MODIFIER_EXPIRED]:
			continue
		var key := "%s:%s" % [event.params.get("scope", "indicator"), event.params.get("target", "")]
		_mark(key, turn)
		_pending[key] = true


func order(entries: Array[Dictionary], state: GameState) -> Array[Dictionary]:
	var shapes := {}
	for modifier in state.modifiers:
		if modifier.is_expired():
			continue
		var key := "%s:%s" % [modifier.scope, modifier.target]
		if not shapes.has(key):
			shapes[key] = []
		# Countdown and per-play progress/used_turn are not new economic effects.
		# Object identity catches replacement by a fresh same-value investment.
		shapes[key].append([modifier.get_instance_id(), modifier.op, modifier.value,
			modifier.stacks, modifier.amount, modifier.rule, modifier.is_active(state.turn),
			modifier.data.get("weakened", false)])
	var result: Array[Dictionary] = []
	for index in entries.size():
		var entry: Dictionary = entries[index].duplicate()
		var key := str(entry["key"])
		var shape := var_to_str(shapes.get(key, []))
		if not _pending.has(key) and ((_shapes.has(key) and _shapes[key] != shape) \
			or (not _shapes.has(key) and shapes.has(key))):
			_mark(key, state.turn)
		_shapes[key] = shape
		var change: Dictionary = _changes.get(key, {})
		entry["change_order"] = int(change.get("order", -1))
		entry["changed_turn"] = int(change.get("turn", -100))
		var age := state.turn - int(entry["changed_turn"])
		entry["recent_change"] = age >= 0 and age <= 1
		entry["current_change"] = age == 0
		entry["original_index"] = index
		result.append(entry)
	# Forget expired badges, so reacquiring one always has a new timestamp.
	for key in _shapes.keys():
		if not entries.any(func(entry: Dictionary) -> bool: return entry["key"] == key):
			_shapes.erase(key)
			_changes.erase(key)
	_pending.clear()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["change_order"] == b["change_order"]:
			return int(a["original_index"]) < int(b["original_index"])
		return int(a["change_order"]) > int(b["change_order"])
	)
	return result


func _mark(key: String, turn: int) -> void:
	_serial += 1
	_changes[key] = {"turn": turn, "order": _serial}
