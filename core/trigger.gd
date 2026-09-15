class_name Trigger
extends RefCounted

var on_kind: int
var effects: Array[Effect] = []


func _init(p_on_kind: int = Event.Kind.CUSTOM, p_effects: Array[Effect] = []) -> void:
	on_kind = p_on_kind
	effects = p_effects


static func from_dict(data: Dictionary) -> Trigger:
	var effects: Array[Effect] = []
	for raw in data.get("effects", []):
		effects.append(Effect.from_dict(raw))
	return Trigger.new(Event.kind_from(data.get("on", "")), effects)
