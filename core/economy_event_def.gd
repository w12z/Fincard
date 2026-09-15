class_name EconomyEventDef
extends RefCounted

var id: StringName
var title: String
var description: String
var effects: Array[Effect] = []
var choices: Array[EventChoice] = []


func has_choices() -> bool:
	return not choices.is_empty()


static func from_dict(data: Dictionary) -> EconomyEventDef:
	var event := EconomyEventDef.new()
	event.id = StringName(data.get("id", ""))
	event.title = data.get("title", "")
	event.description = data.get("description", "")
	for raw in data.get("effects", []):
		event.effects.append(Effect.from_dict(raw))
	for raw in data.get("choices", []):
		event.choices.append(EventChoice.from_dict(raw))
	return event
