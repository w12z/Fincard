class_name StatusRules
extends RefCounted

# Definitions provide names and rules; all live effects are Modifier instances.
static func active_modifiers(state: GameState) -> Array[Modifier]:
	var result: Array[Modifier] = []
	for modifier in state.modifiers:
		if modifier.scope == Modifier.SCOPE_SPECIAL and modifier.is_active(state.turn):
			result.append(modifier)
	return result


static func find_modifier(state: GameState, id: StringName) -> Modifier:
	for modifier in state.modifiers:
		if modifier.scope == Modifier.SCOPE_SPECIAL and modifier.target == id and not modifier.is_expired():
			return modifier
	return null


static func has_rule(state: GameState, _definitions: Dictionary, rule: StringName) -> bool:
	for modifier in active_modifiers(state):
		if modifier.rule == rule:
			return true
	return false


static func allows_deficit(state: GameState, definitions: Dictionary) -> bool:
	return has_rule(state, definitions, &"deficit_spending")


static func mark_triggered(modifier: Modifier, state: GameState) -> Event:
	modifier.data["triggered_turn"] = state.turn
	return Event.new(Event.Kind.STATUS_TRIGGERED, {"status": modifier.target})


static func card_costs(card: CardDef, state: GameState, _definitions: Dictionary) -> Dictionary:
	var budget := card.cost
	var political := card.political_cost
	var sources: Array[StringName] = []
	for modifier in active_modifiers(state):
		match modifier.rule:
			&"second_card_free":
				if state.cards_played_this_turn == 1 and (budget > 0 or political > 0):
					budget = 0
					political = 0
					sources.append(modifier.target)
			&"first_card_political_free":
				if state.cards_played_this_turn == 0 and political > 0:
					political = 0
					sources.append(modifier.target)
			&"first_investment_discount":
				if card.card_type == &"investment" and state.investments_played_this_turn == 0 and budget > 0:
					budget = maxi(0, budget - modifier.amount * modifier.stacks)
					sources.append(modifier.target)
	return {"budget": budget, "political": political, "sources": sources}


static func counter(status: StatusDef, state: GameState) -> String:
	var modifier := find_modifier(state, status.id)
	if modifier == null:
		return "—"
	if not modifier.is_active(state.turn):
		return "下回合生效"
	match modifier.rule:
		&"second_card_free": return "1/1" if state.cards_played_this_turn < 2 else "0/1"
		&"all_types_refund": return "%d/3" % state.flags.get("types_played_this_turn", []).size()
		&"investment_draw": return "%d/%d" % [int(modifier.data.get("progress", 0)), modifier.amount]
		&"aid_card_repeat": return "0/1" if int(modifier.data.get("used_turn", -1)) == state.turn else "1/1"
		&"repeat_next_card": return "%d次" % modifier.stacks
		&"next_turn_replay": return "已记录" if modifier.data.has("queued_card") else "1/1"
		&"retain_card": return "保留1张"
		&"start_turn_review": return "弃1张，抽2张"
		&"save_political": return "最多保留%d点" % (modifier.amount * modifier.stacks)
		&"first_card_political_free": return "1/1" if state.cards_played_this_turn == 0 else "0/1"
		&"first_investment_discount": return "1/1" if state.investments_played_this_turn == 0 else "0/1"
		&"third_card_draw": return "%d/3" % mini(state.cards_played_this_turn, 3)
	return "%d层" % modifier.stacks


static func progress(status: StatusDef, state: GameState) -> String:
	return counter(status, state)


static func ready(status: StatusDef, state: GameState) -> bool:
	var modifier := find_modifier(state, status.id)
	return modifier != null and modifier.is_active(state.turn)
