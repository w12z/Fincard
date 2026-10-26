class_name CardDef
extends RefCounted

const RARITIES: Array[StringName] = [&"common", &"rare", &"legendary", &"special"]
const REWARD_RARITIES: Array[StringName] = [&"common", &"rare", &"legendary"]

var id: StringName
var display_name: String
var description: String
var card_type: StringName
var rarity: StringName = &"common"
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
	card.rarity = StringName(data.get("rarity", "common"))
	card.cost = int(data.get("cost", 0))
	card.political_cost = int(data.get("political_cost", 0))
	card.once_per_run = bool(data.get("once_per_run", false))
	for raw in data.get("effects", []):
		card.effects.append(Effect.from_dict(raw))
	return card
