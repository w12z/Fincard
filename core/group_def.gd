class_name GroupDef
extends RefCounted

var id: StringName
var type: StringName
var display_name: String
var members: Array[StringName] = []


static func from_dict(data: Dictionary) -> GroupDef:
	var group := GroupDef.new()
	group.id = StringName(data.get("id", ""))
	group.type = StringName(data.get("type", ""))
	group.display_name = data.get("display_name", "")
	for item_id in data.get("members", []):
		group.members.append(StringName(item_id))
	return group


func contains(item_id: StringName) -> bool:
	return members.has(item_id)
