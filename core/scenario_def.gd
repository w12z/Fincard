class_name ScenarioDef
extends RefCounted

var id: StringName
var display_name: String
var description: String
var starting_deck: Array[StringName] = []
var indicators: Dictionary = {}
var event_pool: Array[StringName] = []
var innate_modifiers: Array[Effect] = []
var goal: GoalDef
var budget_pool: Array[StringName] = []
var groups: Dictionary = {}
var scheduled_events: Dictionary = {}


static func from_dict(data: Dictionary) -> ScenarioDef:
	var scenario := ScenarioDef.new()
	scenario.id = StringName(data.get("id", ""))
	scenario.display_name = data.get("display_name", "")
	scenario.description = data.get("description", "")
	for card_id in data.get("starting_deck", []):
		scenario.starting_deck.append(StringName(card_id))
	var raw_indicators = data.get("indicators", {})
	if raw_indicators is Dictionary:
		for key in raw_indicators:
			scenario.indicators[StringName(key)] = float(raw_indicators[key])
	for event_id in data.get("event_pool", []):
		scenario.event_pool.append(StringName(event_id))
	for raw in data.get("innate_modifiers", []):
		scenario.innate_modifiers.append(Effect.from_dict(raw))
	var goal_data = data.get("goal")
	if goal_data is Dictionary:
		scenario.goal = GoalDef.from_dict(goal_data)
	for plan_id in data.get("budget_pool", []):
		scenario.budget_pool.append(StringName(plan_id))
	var raw_groups = data.get("groups", {})
	if raw_groups is Array:
		var flat: Array[StringName] = []
		for group_id in raw_groups:
			flat.append(StringName(group_id))
		scenario.groups["*"] = flat
	elif raw_groups is Dictionary:
		for key in raw_groups:
			var list: Array[StringName] = []
			var raw_list = raw_groups[key]
			if raw_list is Array:
				for group_id in raw_list:
					list.append(StringName(group_id))
			scenario.groups[String(key)] = list
	var raw_scheduled = data.get("scheduled_events", [])
	if raw_scheduled is Array:
		for entry in raw_scheduled:
			if entry is Dictionary and entry.has("event"):
				scenario.scheduled_events[int(entry.get("turn", 0))] = StringName(entry.get("event", ""))
	return scenario
