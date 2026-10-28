class_name EffectResolver
extends RefCounted

var economy: EconomyModel
var status_db: Dictionary = {}
var card_db: Dictionary = {}


func resolve(effect: Effect, state: GameState, rng: Rng) -> Array[Event]:
	if effect.condition != null and (economy == null or not effect.condition.evaluate(state, economy)):
		return []
	match effect.kind:
		Effect.Kind.APPLY_MODIFIER:
			return _apply_modifier(effect.params, state)
		Effect.Kind.REMOVE_MODIFIER:
			return _remove_modifier(effect.params, state)
		Effect.Kind.ADJUST_INDICATOR:
			return _adjust_indicator(effect.params, state)
		Effect.Kind.DRAW_CARDS:
			return _draw(effect.params, state, rng)
		Effect.Kind.CHOOSE_DISCARD_DRAW:
			if not state.hand.is_empty():
				var requests: Array = state.flags.get("pending_discard_draw", [])
				requests.append({"draw_count": maxi(0, int(effect.params.get("draw_count", 2)))})
				state.flags["pending_discard_draw"] = requests
			return []
		Effect.Kind.GAIN_BUDGET:
			return _gain_resource(effect.params, state, &"budget")
		Effect.Kind.GAIN_POLITICAL_CAPITAL:
			return _gain_resource(effect.params, state, &"political_capital")
		Effect.Kind.BRANCH:
			return _resolve_branch(effect.params, state, rng)
		Effect.Kind.GRANT_STATUS:
			return _apply_modifier({"scope": "special", "target": effect.params.get("status", ""), "duration": -1, "stacks": 1}, state)
		Effect.Kind.GAIN_CARD:
			var id := StringName(effect.params.get("card", ""))
			var card: CardDef = card_db.get(id)
			if card == null:
				push_error("Unknown granted card: %s" % id)
				return []
			if card.once_per_run and (state.flags.get("enacted:" + String(id), false) or state.deck.has(id) or state.hand.has(id) or state.discard.has(id)):
				return []
			state.deck.append(id)
			return [Event.new(Event.Kind.CARD_GAINED, {"card_id": id})]
		_:
			return []


func _resolve_branch(params: Dictionary, state: GameState, rng: Rng) -> Array[Event]:
	var raw_condition = params.get("condition")
	if raw_condition is Dictionary and economy != null:
		if Condition.from_dict(raw_condition).evaluate(state, economy):
			return _resolve_effects(params.get("then", []), state, rng)
		return _resolve_effects(params.get("else", []), state, rng)
	return _resolve_effects(params.get("then", []), state, rng)


func _resolve_effects(raw_list: Variant, state: GameState, rng: Rng) -> Array[Event]:
	if not (raw_list is Array):
		return []
	var events: Array[Event] = []
	for raw in raw_list:
		if raw is Dictionary:
			events.append_array(resolve(Effect.from_dict(raw), state, rng))
	return events


func _apply_modifier(params: Dictionary, state: GameState) -> Array[Event]:
	var modifier := Modifier.new(
		StringName(params.get("target", "")),
		Modifier.op_from(params.get("op", "add")),
		float(params.get("value", 0.0)),
		int(params.get("duration", 0)),
		StringName(params.get("source", "")),
		StringName(params.get("scope", "indicator"))
	)
	modifier.stacks = maxi(1, int(params.get("stacks", 1)))
	if modifier.scope == Modifier.SCOPE_SPECIAL:
		var definition: StatusDef = status_db.get(modifier.target)
		modifier.rule = StringName(params.get("rule", definition.rule if definition != null else ""))
		modifier.amount = int(params.get("amount", definition.amount if definition != null else 1))
		modifier.data = definition.parameters.duplicate(true) if definition != null else {}
		modifier.data.merge(params.get("data", {}), true)
		if modifier.data.get("allow_zero_stacks", false):
			modifier.stacks = maxi(0, int(params.get("stacks", 0)))
		modifier.ready_turn = state.turn + (1 if definition != null and definition.start_next_turn else 0)
		if modifier.source == &"" and definition != null:
			modifier.source = StringName(definition.display_name)
		if modifier.rule == &"":
			push_error("Unknown special modifier: %s" % modifier.target)
			return []
		for existing in state.modifiers:
			if existing.scope != Modifier.SCOPE_SPECIAL or existing.target != modifier.target or existing.is_expired():
				continue
			if definition == null or definition.stackable:
				existing.stacks += modifier.stacks
				if modifier.is_permanent():
					existing.remaining_turns = -1
				elif not existing.is_permanent():
					existing.remaining_turns = maxi(existing.remaining_turns, modifier.remaining_turns)
				return [Event.new(Event.Kind.MODIFIER_APPLIED, {"target": existing.target, "scope": existing.scope, "op": existing.op, "source": existing.source})]
			return []
	state.modifiers.append(modifier)
	return [Event.new(Event.Kind.MODIFIER_APPLIED, {
		"target": modifier.target,
		"op": modifier.op,
		"scope": modifier.scope,
		"source": modifier.source,
	})]


func _remove_modifier(params: Dictionary, state: GameState) -> Array[Event]:
	var target := StringName(params.get("target", ""))
	var source := StringName(params.get("source", ""))
	var scope := StringName(params.get("scope", ""))
	var kept: Array[Modifier] = []
	var events: Array[Event] = []
	for modifier in state.modifiers:
		var matches_target := target == &"" or modifier.target == target
		var matches_source := source == &"" or modifier.source == source
		var matches_scope := scope == &"" or modifier.scope == scope
		var matches_duration := not bool(params.get("temporary_only", false)) or not modifier.is_permanent()
		var matches_positive := not bool(params.get("positive_only", false)) or _is_positive_modifier(modifier, state)
		if matches_target and matches_source and matches_scope and matches_duration and matches_positive:
			events.append(Event.new(Event.Kind.MODIFIER_EXPIRED, {
				"target": modifier.target,
				"scope": modifier.scope,
				"source": modifier.source,
			}))
		else:
			kept.append(modifier)
	state.modifiers = kept
	return events


func _is_positive_modifier(modifier: Modifier, state: GameState) -> bool:
	match modifier.op:
		Modifier.Op.ADD:
			return modifier.effective_value() > 0.0
		Modifier.Op.MUL:
			return modifier.effective_value() > 1.0
		Modifier.Op.OVERRIDE:
			if modifier.scope == Modifier.SCOPE_COEFFICIENT and economy != null:
				var base := float(economy.scenario_coefficients.get(modifier.target, economy.base_coefficients.get(modifier.target, 0.0)))
				return modifier.effective_value() > base
			return modifier.effective_value() > float(state.indicators.get(modifier.target, 0.0))
	return false


func _adjust_indicator(params: Dictionary, state: GameState) -> Array[Event]:
	var target := StringName(params.get("target", ""))
	var delta := float(params.get("amount", 0.0))
	if bool(params.get("percent", false)):
		if target == &"gdp":
			var gdp := float(state.indicators.get(&"gdp", 0.0))
			delta = delta / 100.0 * gdp
		else:
			push_warning("percent 仅适用于 gdp，已按绝对值处理：%s" % target)
	var previous := float(state.indicators.get(target, 0.0))
	state.indicators[target] = previous + delta
	if economy != null:
		economy.clamp_indicator(state, target)
	delta = float(state.indicators.get(target, 0.0)) - previous
	return [Event.new(Event.Kind.INDICATOR_CHANGED, {
		"indicator": target,
		"previous": previous,
		"current": previous + delta,
		"delta": delta,
	})]


func _draw(params: Dictionary, state: GameState, rng: Rng) -> Array[Event]:
	var count := int(params.get("count", 0))
	var drawn := 0
	while drawn < count and state.draw_card(rng):
		drawn += 1
	if drawn == 0:
		return []
	return [Event.new(Event.Kind.CARDS_DRAWN, {"count": drawn})]


func _gain_resource(params: Dictionary, state: GameState, resource: StringName) -> Array[Event]:
	var amount := int(params.get("amount", 0))
	if resource == &"budget" and params.has("per_investment_played"):
		amount += state.investments_played_this_turn * int(params["per_investment_played"])
		amount = mini(amount, int(params.get("cap", amount)))
	if resource == &"budget":
		state.budget += amount
	else:
		state.political_capital += amount
	return [Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": resource, "amount": amount})]
