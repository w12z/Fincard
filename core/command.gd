class_name Command
extends RefCounted

enum Kind { PLAY_CARD, END_TURN, RESOLVE_EVENT, USE_AID, CHOOSE_REWARD, CHOOSE_RETAINED_CARD, CHOOSE_REVIEW_CARD, CLAIM_REWARD, CHOOSE_DISCARD_CARD, CHOOSE_REMOVED_CARD }

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


static func choose_reward(picks: Array) -> Command:
	return Command.new(Kind.CHOOSE_REWARD, {"picks": picks})


static func choose_retained_card(hand_index: int) -> Command:
	return Command.new(Kind.CHOOSE_RETAINED_CARD, {"hand_index": hand_index})


static func choose_review_card(hand_index: int) -> Command:
	return Command.new(Kind.CHOOSE_REVIEW_CARD, {"hand_index": hand_index})


static func claim_reward(group_index: int, option_index: int, token: String = "") -> Command:
	return Command.new(Kind.CLAIM_REWARD, {"group_index": group_index, "option_index": option_index, "token": token})


static func choose_discard_card(hand_index: int) -> Command:
	return Command.new(Kind.CHOOSE_DISCARD_CARD, {"hand_index": hand_index})


static func choose_removed_card(group_index: int, token: String, card_id: StringName = &"") -> Command:
	return Command.new(Kind.CHOOSE_REMOVED_CARD, {"group_index": group_index, "token": token, "card_id": card_id})
