class_name Reward
extends RefCounted

enum Type { CARD, CABINET, AID }

const TYPE_NAMES := {
	"card": Type.CARD,
	"cabinet": Type.CABINET,
	"aid": Type.AID,
}

var type: int
var id: StringName
var label: String


func _init(p_type: int = Type.CARD, p_id: StringName = &"", p_label: String = "") -> void:
	type = p_type
	id = p_id
	label = p_label
