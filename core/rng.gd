class_name Rng
extends RefCounted

const _POSITIVE_MASK := 0x7FFFFFFFFFFFFFFF
const _MULTIPLIER := 6364136223846793005
const _INCREMENT := 1442695040888963407

var _state: int


func _init(seed_value: int) -> void:
	_state = seed_value if seed_value != 0 else 1


func next_int(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return (_next_u64() & _POSITIVE_MASK) % max_exclusive


func next_float() -> float:
	return float(_next_u64() & _POSITIVE_MASK) / float(_POSITIVE_MASK)


func pick(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[next_int(array.size())]


func shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := next_int(i + 1)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp


func _next_u64() -> int:
	_state = _state * _MULTIPLIER + _INCREMENT
	return _state
