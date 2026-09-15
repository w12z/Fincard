class_name Command
extends RefCounted

enum Kind { PLAY_CARD, END_TURN, RESOLVE_EVENT, USE_AID, CHOOSE_BUDGET, CHOOSE_REWARD }

var kind: int
var params: Dictionary


func _init(p_kind: int, p_params: Dictionary = {}) -> void:
	kind = p_kind
	params = p_params


static func play_card(card_id: StringName) -> Command:
	return Command.new(Kind.PLAY_CARD, {"card_id": card_id})


static func end_turn() -> Command:
	return Command.new(Kind.END_TURN)


static func resolve_event(choice_index: int) -> Command:
	return Command.new(Kind.RESOLVE_EVENT, {"choice_index": choice_index})


static func use_aid(aid_id: StringName) -> Command:
	return Command.new(Kind.USE_AID, {"aid_id": aid_id})


static func choose_budget(plan_id: StringName) -> Command:
	return Command.new(Kind.CHOOSE_BUDGET, {"plan_id": plan_id})


static func choose_reward(picks: Array) -> Command:
	return Command.new(Kind.CHOOSE_REWARD, {"picks": picks})
