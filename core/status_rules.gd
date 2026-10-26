class_name StatusRules
extends RefCounted


static func allows_deficit(state: GameState, definitions: Dictionary) -> bool:
	for id in state.statuses:
		var status: StatusDef = definitions.get(id)
		if status != null and status.rule == &"deficit_spending":
			return true
	return false


static func card_costs(card: CardDef, state: GameState, definitions: Dictionary) -> Dictionary:
	var budget := card.cost
	var political := card.political_cost
	var sources: Array[StringName] = []
	for id in state.statuses:
		var status: StatusDef = definitions.get(id)
		if status == null:
			continue
		match status.rule:
			&"first_card_political_free":
				if state.cards_played_this_turn == 0 and political > 0:
					political = 0
					sources.append(id)
			&"first_investment_discount":
				if card.card_type == &"investment" and state.investments_played_this_turn == 0 and budget > 0:
					budget = maxi(0, budget - status.amount)
					sources.append(id)
	return {"budget": budget, "political": political, "sources": sources}


static func progress(status: StatusDef, state: GameState) -> String:
	match status.rule:
		&"first_card_political_free":
			return "可用 1/1" if state.cards_played_this_turn == 0 else "已用 0/1"
		&"first_investment_discount":
			return "可用 1/1" if state.investments_played_this_turn == 0 else "已用 0/1"
		&"third_card_draw":
			if state.cards_played_this_turn < 3:
				return "进度 %d/3" % state.cards_played_this_turn
			return "本回合已触发" if state.statuses_triggered_this_turn.has(status.id) else "下回合可触发"
	return "永久生效"


static func ready(status: StatusDef, state: GameState) -> bool:
	match status.rule:
		&"first_card_political_free": return state.cards_played_this_turn == 0
		&"first_investment_discount": return state.investments_played_this_turn == 0
		&"third_card_draw": return state.cards_played_this_turn < 3
	return true


static func counter(status: StatusDef, state: GameState) -> String:
	match status.rule:
		&"first_card_political_free": return "1/1" if state.cards_played_this_turn == 0 else "0/1"
		&"first_investment_discount": return "1/1" if state.investments_played_this_turn == 0 else "0/1"
		&"third_card_draw":
			if state.cards_played_this_turn < 3:
				return "%d/3" % state.cards_played_this_turn
			return "✓" if state.statuses_triggered_this_turn.has(status.id) else "—"
	return "∞"
