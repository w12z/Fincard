class_name Condition
extends RefCounted

enum Comparator { GE, LE, GT, LT, EQ }

const COMPARATOR_NAMES := {
	"ge": Comparator.GE,
	"le": Comparator.LE,
	"gt": Comparator.GT,
	"lt": Comparator.LT,
	"eq": Comparator.EQ,
}

var indicator: StringName
var comparator: int
var value: float


func _init(p_indicator: StringName = &"", p_comparator: int = Comparator.GE, p_value: float = 0.0) -> void:
	indicator = p_indicator
	comparator = p_comparator
	value = p_value


func evaluate(state: GameState, economy: EconomyModel) -> bool:
	var current := economy.value(state, indicator)
	match comparator:
		Comparator.GE:
			return current >= value
		Comparator.LE:
			return current <= value
		Comparator.GT:
			return current > value
		Comparator.LT:
			return current < value
		Comparator.EQ:
			return is_equal_approx(current, value)
	return false


static func from_dict(data: Dictionary) -> Condition:
	return Condition.new(
		StringName(data.get("indicator", "")),
		COMPARATOR_NAMES.get(data.get("comparator", "ge"), Comparator.GE),
		float(data.get("value", 0.0))
	)
