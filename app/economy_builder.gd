class_name EconomyBuilder
extends RefCounted


static func build(economy: EconomyModel, config: Dictionary, rules: Dictionary) -> void:
	var raw: Dictionary = config.get("coefficients", {})
	var base: Dictionary = {}
	for key in raw:
		base[StringName(key)] = float(raw[key])
	economy.base_coefficients = base

	economy.equations[&"gdp"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var gdp := model.value(state, &"gdp")
		var g_rate := EconomyBuilder._growth_rate(state, model)
		return gdp * g_rate / 100.0

	economy.equations[&"inflation"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var g_rate := EconomyBuilder._growth_rate(state, model)
		var gap := model.coefficient(state, &"inflation_target") - model.value(state, &"inflation")
		return (gap + g_rate) / 10.0 + model.coefficient(state, &"infl_anchor") * gap

	economy.equations[&"unemployment"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var gap := model.coefficient(state, &"natural_unemployment") - model.value(state, &"unemployment")
		var growth := EconomyBuilder._growth_rate(state, model)
		var growth_impact := growth / 8.0 if growth > 0.0 else growth / 2.0
		return gap / 10.0 - growth_impact \
			- model.coefficient(state, &"u_revert") * maxf(-gap, 0.0)

	economy.equations[&"confidence"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var growth := EconomyBuilder._growth_rate(state, model)
		var confidence := model.value(state, &"confidence")
		var growth_impact := growth / 2.0 if growth > 0.0 else growth
		return growth_impact \
			- absf(model.value(state, &"inflation") - model.coefficient(state, &"inflation_target")) / 5.0 \
			- maxf(model.value(state, &"unemployment") - model.coefficient(state, &"natural_unemployment"), 0.0) / 5.0 \
			- maxf(-float(state.budget), 0.0) / 5.0 \
			- maxf(50.0 - confidence, 0.0) * 0.1 \
			+ EconomyBuilder.special_confidence_delta(state, growth)

	economy.register_derived(&"growth", func(state: GameState, model: EconomyModel) -> float:
		return EconomyBuilder._growth_rate(state, model)
	)

	for id in config.get("bounds", {}):
		var pair = config.get("bounds")[id]
		if pair is Array and pair.size() == 2:
			economy.set_bounds(StringName(id), float(pair[0]), float(pair[1]))
	economy.base_bounds = economy.bounds.duplicate(true)


static func special_confidence_delta(state: GameState, growth: float) -> float:
	var delta := 0.0
	for modifier in StatusRules.active_modifiers(state):
		match modifier.rule:
			&"growth_confidence_bonus":
				if state.turn <= int(modifier.data.get("last_turn", 16)):
					var step := float(modifier.data.get("growth_step", 0.2))
					if step > 0.0:
						var steps := floorf((maxf(growth, 0.0) + 0.00000001) / step)
						delta += minf(float(modifier.data.get("confidence_cap", 6)), steps * float(modifier.data.get("confidence_per_step", 2))) * modifier.stacks
			&"negative_growth_confidence":
				delta -= maxf(-growth, 0.0) * StatusRules.confidence_crash_rate(modifier, state.turn) * modifier.stacks
	return delta


static func _growth_rate(state: GameState, model: EconomyModel) -> float:
	var rate := model.coefficient(state, &"gdp_auto") \
		+ model.value(state, &"confidence") / 100.0 \
		- model.value(state, &"interest_rate") / 10.0
	var pair: Array = model.bounds.get(&"growth", [])
	return clampf(rate, float(pair[0]), float(pair[1])) if pair.size() == 2 else rate
