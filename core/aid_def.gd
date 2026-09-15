class_name AidDef
extends RefCounted

var id: StringName
var display_name: String
var description: String
var uses: int
var effects: Array[Effect] = []


static func from_dict(data: Dictionary) -> AidDef:
	var aid := AidDef.new()
	aid.id = StringName(data.get("id", ""))
	aid.display_name = data.get("display_name", "")
	aid.description = data.get("description", "")
	aid.uses = int(data.get("uses", 1))
	for raw in data.get("effects", []):
		aid.effects.append(Effect.from_dict(raw))
	return aid
