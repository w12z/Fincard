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
		return gap / 10.0 - EconomyBuilder._growth_rate(state, model) / 2.0 \
			- model.coefficient(state, &"u_revert") * maxf(-gap, 0.0)

	economy.equations[&"confidence"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		return EconomyBuilder._growth_rate(state, model) \
			- absf(model.value(state, &"inflation") - model.coefficient(state, &"inflation_target")) / 5.0 \
			- maxf(model.value(state, &"unemployment") - model.coefficient(state, &"natural_unemployment"), 0.0) / 5.0 \
			- maxf(-float(state.budget), 0.0) / 5.0

	economy.register_derived(&"growth", func(state: GameState, model: EconomyModel) -> float:
		return EconomyBuilder._growth_rate(state, model)
	)

	for id in config.get("bounds", {}):
		var pair = config.get("bounds")[id]
		if pair is Array and pair.size() == 2:
			economy.set_bounds(StringName(id), float(pair[0]), float(pair[1]))
	economy.base_bounds = economy.bounds.duplicate(true)


static func _growth_rate(state: GameState, model: EconomyModel) -> float:
	var rate := model.coefficient(state, &"gdp_auto") \
		+ model.value(state, &"confidence") / 100.0 \
		- model.value(state, &"interest_rate") / 10.0
	var pair: Array = model.bounds.get(&"growth", [])
	return clampf(rate, float(pair[0]), float(pair[1])) if pair.size() == 2 else rate
