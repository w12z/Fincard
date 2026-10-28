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


static func confidence_crash_rate(modifier: Modifier, turn: int) -> float:
	var expire_turn := int(modifier.data.get("expire_turn", 0))
	if expire_turn > 0 and turn >= expire_turn:
		return 0.0
	var rate := float(modifier.data.get("confidence_per_percent", 2))
	var weaken_turn := int(modifier.data.get("weaken_turn", 0))
	if weaken_turn > 0 and turn >= weaken_turn:
		rate *= float(modifier.data.get("weaken_multiplier", 0.5))
	return rate


static func mark_triggered(modifier: Modifier, state: GameState) -> Event:
	modifier.data["triggered_turn"] = state.turn
	return Event.new(Event.Kind.STATUS_TRIGGERED, {"status": modifier.target})


static func provides_political(card: CardDef, state: GameState, economy: EconomyModel) -> bool:
	return _provides_political(card.effects, state, economy)


static func _provides_political(effects: Array, state: GameState, economy: EconomyModel) -> bool:
	for effect: Effect in effects:
		if effect.condition != null and (economy == null or not effect.condition.evaluate(state, economy)):
			continue
		if effect.kind == Effect.Kind.GAIN_POLITICAL_CAPITAL and int(effect.params.get("amount", 0)) > 0:
			return true
		if effect.kind == Effect.Kind.BRANCH and economy != null:
			var condition := Condition.from_dict(effect.params.get("condition", {}))
			var branch: Array[Effect] = []
			for raw in effect.params.get("then" if condition.evaluate(state, economy) else "else", []):
				branch.append(Effect.from_dict(raw))
			if _provides_political(branch, state, economy):
				return true
	return false


static func card_costs(card: CardDef, state: GameState, _definitions: Dictionary, economy: EconomyModel = null) -> Dictionary:
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
			&"next_investment_discount":
				if card.card_type == &"investment" and budget > 0:
					budget = maxi(0, budget - modifier.amount * modifier.stacks)
					sources.append(modifier.target)
			&"second_investment_discount":
				if card.card_type == &"investment" and state.investments_played_this_turn == 1 and budget > 0:
					budget = maxi(0, budget - modifier.amount * modifier.stacks)
					sources.append(modifier.target)
			&"first_political_policy_discount":
				if card.card_type == &"policy" and int(state.flags.get("political_policies_played_this_turn", 0)) == 0 and provides_political(card, state, economy) and budget > 0:
					budget = maxi(0, budget - modifier.amount * modifier.stacks)
					sources.append(modifier.target)
			&"second_policy_discount":
				if card.card_type == &"policy" and int(state.flags.get("policies_played_this_turn", 0)) == 1 and budget > 0:
					budget = maxi(0, budget - modifier.amount * modifier.stacks)
					sources.append(modifier.target)
			&"next_investment_political_discount":
				if card.card_type == &"investment" and political > 0:
					political = maxi(0, political - modifier.amount * modifier.stacks)
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
		&"all_types_refund":
			var types: Array = state.flags.get("types_played_this_turn", [])
			return "%d/2" % (int(types.has(&"investment")) + int(types.has(&"policy")))
		&"investment_draw": return "%d/%d" % [int(modifier.data.get("progress", 0)), modifier.amount]
		&"aid_card_repeat": return "0/1" if int(modifier.data.get("used_turn", -1)) == state.turn else "1/1"
		&"repeat_next_card": return "%d次" % modifier.stacks
		&"next_turn_replay": return "已记录" if modifier.data.has("queued_card") else "1/1"
		&"retain_card": return "保留1张"
		&"start_turn_review": return "弃1张，抽2张"
		&"save_political": return "最多保留%d点" % (modifier.amount * modifier.stacks)
		&"first_card_political_free": return "1/1" if state.cards_played_this_turn == 0 else "0/1"
		&"first_investment_discount": return "1/1" if state.investments_played_this_turn == 0 else "0/1"
		&"next_investment_discount": return "预算成本 -%d" % (modifier.amount * modifier.stacks)
		&"next_investment_political_discount": return "政治成本 -%d" % (modifier.amount * modifier.stacks)
		&"second_investment_discount", &"second_investment_budget": return "%d/2" % mini(state.investments_played_this_turn, 2)
		&"second_policy_discount": return "%d/2" % mini(int(state.flags.get("policies_played_this_turn", 0)), 2)
		&"third_card_budget": return "%d/3" % mini(state.cards_played_this_turn, 3)
		&"first_growth_extension", &"first_job_confidence", &"first_confidence_employment", &"first_political_policy_discount":
			return "0/1" if int(modifier.data.get("triggered_turn", -1)) == state.turn else "1/1"
		&"third_card_draw": return "%d/3" % mini(state.cards_played_this_turn, 3)
	return "%d层" % modifier.stacks


static func progress(status: StatusDef, state: GameState) -> String:
	return counter(status, state)


static func ready(status: StatusDef, state: GameState) -> bool:
	var modifier := find_modifier(state, status.id)
	return modifier != null and modifier.is_active(state.turn)
