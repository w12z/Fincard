class_name StatusDef
extends RefCounted

var id: StringName
var display_name: String
var description: String
var icon: String
var rule: StringName
var amount: int
var start_next_turn: bool = false
var stackable: bool = false


static func from_dict(data: Dictionary) -> StatusDef:
	var status := StatusDef.new()
	status.id = StringName(data.get("id", ""))
	status.display_name = data.get("display_name", "")
	status.description = data.get("description", "")
	status.icon = data.get("icon", "★")
	status.rule = StringName(data.get("rule", ""))
	status.amount = int(data.get("amount", 1))
	status.start_next_turn = bool(data.get("start_next_turn", false))
	status.stackable = bool(data.get("stackable", false))
	return status
