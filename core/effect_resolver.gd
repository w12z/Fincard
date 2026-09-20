class_name EffectResolver
extends RefCounted

var economy: EconomyModel


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
		Effect.Kind.GAIN_BUDGET:
			return _gain_resource(effect.params, state, &"budget")
		Effect.Kind.GAIN_POLITICAL_CAPITAL:
			return _gain_resource(effect.params, state, &"political_capital")
		Effect.Kind.BRANCH:
			return _resolve_branch(effect.params, state, rng)
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
		if matches_target and matches_source and matches_scope:
			events.append(Event.new(Event.Kind.MODIFIER_EXPIRED, {
				"target": modifier.target,
				"scope": modifier.scope,
				"source": modifier.source,
			}))
		else:
			kept.append(modifier)
	state.modifiers = kept
	return events


func _adjust_indicator(params: Dictionary, state: GameState) -> Array[Event]:
	var target := StringName(params.get("target", ""))
	var delta := float(params.get("amount", 0.0))
	if bool(params.get("percent", false)):
		if target == &"gdp" or target == &"debt":
			var gdp := float(state.indicators.get(&"gdp", 0.0))
			delta = delta / 100.0 * gdp
		else:
			push_warning("percent 仅适用于 gdp/debt，已按绝对值处理：%s" % target)
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
	if resource == &"budget":
		state.budget += amount
	else:
		state.political_capital += amount
	return [Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": resource, "amount": amount})]
