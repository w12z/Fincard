class_name Modifier
extends RefCounted

enum Op { ADD, MUL, OVERRIDE }

const SCOPE_INDICATOR := &"indicator"
const SCOPE_COEFFICIENT := &"coefficient"
const SCOPE_FISCAL := &"fiscal"
const SCOPE_REWARD := &"reward"
const SCOPE_SPECIAL := &"special"

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
var stacks: int = 1
var rule: StringName = &""
var amount: int = 1
var ready_turn: int = 0
var data: Dictionary = {}


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
	return remaining_turns == 0 or (stacks <= 0 and not bool(data.get("allow_zero_stacks", false)))


func is_active(turn: int) -> bool:
	return not is_expired() and turn >= ready_turn


func effective_value() -> float:
	if op == Op.MUL:
		return pow(value, stacks)
	return value * stacks if op == Op.ADD else value


func snapshot() -> Modifier:
	var copy := Modifier.new(target, op, value, remaining_turns, source, scope)
	copy.stacks = stacks
	copy.rule = rule
	copy.amount = amount
	copy.ready_turn = ready_turn
	copy.data = data.duplicate(true)
	return copy


func advance_turn() -> void:
	if remaining_turns > 0:
		remaining_turns -= 1
