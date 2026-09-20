class_name GoalDef
extends RefCounted

var description: String
var deadline_years: int
var after_turn: int
var conditions: Array[Condition] = []
var loss_conditions: Array[Condition] = []


func is_achieved(state: GameState, economy: EconomyModel) -> bool:
	if conditions.is_empty():
		return false
	for condition in conditions:
		if not condition.evaluate(state, economy):
			return false
	return true


func is_failed(state: GameState, economy: EconomyModel) -> bool:
	for condition in loss_conditions:
		if condition.evaluate(state, economy):
			return true
	return false


static func from_dict(data: Dictionary) -> GoalDef:
	var goal := GoalDef.new()
	goal.description = data.get("description", "")
	goal.deadline_years = int(data.get("deadline_years", 0))
	goal.after_turn = int(data.get("after_turn", 0))
	for raw in data.get("conditions", []):
		goal.conditions.append(Condition.from_dict(raw))
	for raw in data.get("loss_conditions", []):
		goal.loss_conditions.append(Condition.from_dict(raw))
	return goal
