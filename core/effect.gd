class_name Effect
extends RefCounted

enum Kind {
	APPLY_MODIFIER,
	REMOVE_MODIFIER,
	ADJUST_INDICATOR,
	DRAW_CARDS,
	GAIN_BUDGET,
	GAIN_POLITICAL_CAPITAL,
	CUSTOM,
}

const KIND_NAMES := {
	"apply_modifier": Kind.APPLY_MODIFIER,
	"remove_modifier": Kind.REMOVE_MODIFIER,
	"adjust_indicator": Kind.ADJUST_INDICATOR,
	"draw_cards": Kind.DRAW_CARDS,
	"gain_budget": Kind.GAIN_BUDGET,
	"gain_political_capital": Kind.GAIN_POLITICAL_CAPITAL,
	"custom": Kind.CUSTOM,
}

var kind: int
var params: Dictionary
var condition: Condition


func _init(p_kind: int, p_params: Dictionary = {}) -> void:
	kind = p_kind
	params = p_params


static func from_dict(data: Dictionary) -> Effect:
	var effect := Effect.new(kind_from(data.get("kind", "")), data.get("params", {}))
	var raw_condition = data.get("condition")
	if raw_condition is Dictionary:
		effect.condition = Condition.from_dict(raw_condition)
	return effect


static func kind_from(value) -> int:
	if value is String:
		return KIND_NAMES.get(value, Kind.CUSTOM)
	return int(value)
