class_name Modifier
extends RefCounted

enum Op { ADD, MUL, OVERRIDE }

const SCOPE_INDICATOR := &"indicator"
const SCOPE_COEFFICIENT := &"coefficient"

const OP_NAMES := {
	"add": Op.ADD,
	"mul": Op.MUL,
	"override": Op.OVERRIDE,
}
const OP_LABELS := {
	Op.ADD: "增加",
	Op.MUL: "乘以",
	Op.OVERRIDE: "设为",
}

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


static func op_from(value) -> int:
	if value is String:
		return OP_NAMES.get(value, Op.ADD)
	return int(value)


static func op_label(op: int) -> String:
	return OP_LABELS.get(op, "?")


func is_permanent() -> bool:
	return remaining_turns < 0


func is_expired() -> bool:
	return remaining_turns == 0


func advance_turn() -> void:
	if remaining_turns > 0:
		remaining_turns -= 1
