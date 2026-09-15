class_name GroupDef
extends RefCounted

const TYPES := ["cards", "cabinets", "aids", "budgets", "events"]

var id: StringName
var display_name: String
var members: Dictionary = {}


static func from_dict(data: Dictionary) -> GroupDef:
	var group := GroupDef.new()
	group.id = StringName(data.get("id", ""))
	group.display_name = data.get("display_name", "")
	for type in TYPES:
		var list: Array[StringName] = []
		var raw = data.get(type, [])
		if raw is Array:
			for item_id in raw:
				list.append(StringName(item_id))
		group.members[type] = list
	return group


func contains(type: String, item_id: StringName) -> bool:
	var list: Array = members.get(type, [])
	return list.has(item_id)
