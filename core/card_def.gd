class_name CardDef
extends RefCounted

var id: StringName
var display_name: String
var description: String
var cost: int
var political_cost: int
var tags: Array[StringName] = []
var effects: Array[Effect] = []


static func from_dict(data: Dictionary) -> CardDef:
	var card := CardDef.new()
	card.id = StringName(data.get("id", ""))
	card.display_name = data.get("display_name", "")
	card.description = data.get("description", "")
	card.cost = int(data.get("cost", 0))
	card.political_cost = int(data.get("political_cost", 0))
	for tag in data.get("tags", []):
		card.tags.append(StringName(tag))
	for raw in data.get("effects", []):
		card.effects.append(Effect.from_dict(raw))
	return card
