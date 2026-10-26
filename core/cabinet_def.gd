class_name CabinetDef
extends RefCounted

var id: StringName
var display_name: String
var description: String
var rarity: StringName = &"common"
var modifiers: Array[Effect] = []
var triggers: Array[Trigger] = []


static func from_dict(data: Dictionary) -> CabinetDef:
	var cabinet := CabinetDef.new()
	cabinet.id = StringName(data.get("id", ""))
	cabinet.display_name = data.get("display_name", "")
	cabinet.description = data.get("description", "")
	cabinet.rarity = StringName(data.get("rarity", "common"))
	for raw in data.get("modifiers", []):
		cabinet.modifiers.append(Effect.from_dict(raw))
	for raw in data.get("triggers", []):
		cabinet.triggers.append(Trigger.from_dict(raw))
	return cabinet
