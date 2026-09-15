class_name BudgetPlanDef
extends RefCounted

var id: StringName
var display_name: String
var description: String
var budget: int
var political_capital: int
var scale: float
var effects: Array[Effect] = []


static func from_dict(data: Dictionary) -> BudgetPlanDef:
	var plan := BudgetPlanDef.new()
	plan.id = StringName(data.get("id", ""))
	plan.display_name = data.get("display_name", "")
	plan.description = data.get("description", "")
	plan.budget = int(data.get("budget", 0))
	plan.political_capital = int(data.get("political_capital", 0))
	plan.scale = float(data.get("scale", 0.0))
	for raw in data.get("effects", []):
		plan.effects.append(Effect.from_dict(raw))
	return plan
