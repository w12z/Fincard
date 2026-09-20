class_name CardDef
extends RefCounted

var id: StringName
var display_name: String
var description: String
var card_type: StringName
var cost: int
var political_cost: int
var once_per_run: bool
var effects: Array[Effect] = []


static func from_dict(data: Dictionary) -> CardDef:
	var card := CardDef.new()
	card.id = StringName(data.get("id", ""))
	card.display_name = data.get("display_name", "")
	card.description = data.get("description", "")
	card.card_type = StringName(data.get("card_type", "investment"))
	card.cost = int(data.get("cost", 0))
	card.political_cost = int(data.get("political_cost", 0))
	card.once_per_run = bool(data.get("once_per_run", false))
	for raw in data.get("effects", []):
		card.effects.append(Effect.from_dict(raw))
	return card
