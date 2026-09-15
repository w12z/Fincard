class_name EventChoice
extends RefCounted

var label: String
var description: String
var effects: Array[Effect] = []


func _init(p_label: String = "", p_description: String = "", p_effects: Array[Effect] = []) -> void:
	label = p_label
	description = p_description
	effects = p_effects


static func from_dict(data: Dictionary) -> EventChoice:
	var effects: Array[Effect] = []
	for raw in data.get("effects", []):
		effects.append(Effect.from_dict(raw))
	return EventChoice.new(data.get("label", ""), data.get("description", ""), effects)
