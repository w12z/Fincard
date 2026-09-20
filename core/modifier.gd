class_name Modifier
extends RefCounted

enum Op { ADD, MUL, OVERRIDE }

const PERMANENT := -1
const SCOPE_INDICATOR := &"indicator"
const SCOPE_COEFFICIENT := &"coefficient"

var scope: StringName
var target: StringName
var op: int
var value: float
var remaining_turns: int
var source: StringName


func _init(p_target: StringName, p_op: int, p_value: float, p_duration: int, p_source: StringName = &"", p_scope: StringName = &"indicator") -> void:
	scope = p_scope
	target = p_target
	op = p_op
	value = p_value
	remaining_turns = p_duration
	source = p_source


func is_permanent() -> bool:
	return remaining_turns < 0


func is_expired() -> bool:
	return remaining_turns == 0


func advance_turn() -> void:
	if remaining_turns > 0:
		remaining_turns -= 1
