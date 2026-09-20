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
		var g_rate := model.value(state, &"growth")
		return model.coefficient(state, &"infl_anchor") * (model.coefficient(state, &"inflation_target") - model.value(state, &"inflation")) \
			+ model.coefficient(state, &"infl_phillips") * (model.coefficient(state, &"natural_unemployment") - model.value(state, &"unemployment")) \
			+ model.coefficient(state, &"infl_demand") * g_rate \
			- model.coefficient(state, &"infl_rate") * (model.value(state, &"interest_rate") - model.coefficient(state, &"neutral_rate"))

	economy.equations[&"unemployment"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		return model.coefficient(state, &"u_revert") * (model.coefficient(state, &"natural_unemployment") - model.value(state, &"unemployment")) \
			- model.coefficient(state, &"u_okun") * model.value(state, &"growth")

	economy.equations[&"debt"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var gdp := model.value(state, &"gdp")
		var ratio := EconomyBuilder._debt_ratio(state, model)
		var revenue := model.coefficient(state, &"debt_rev") * (model.value(state, &"tax_rate") / 100.0)
		var burden := model.coefficient(state, &"debt_int_pass") * ratio * (model.value(state, &"interest_rate") / 100.0)
		return gdp * (-revenue + burden)

	economy.equations[&"confidence"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var threshold := model.coefficient(state, &"debt_threshold")
		var crowding := maxf(0.0, EconomyBuilder._debt_ratio(state, model) - threshold)
		return model.coefficient(state, &"conf_growth") * model.value(state, &"growth") \
			- model.coefficient(state, &"conf_infl") * model.value(state, &"inflation") \
			- model.coefficient(state, &"conf_debt") * crowding \
			+ model.coefficient(state, &"conf_anchor") * (model.coefficient(state, &"confidence_neutral") - model.value(state, &"confidence"))

	economy.register_derived(&"growth", func(state: GameState, model: EconomyModel) -> float:
		return EconomyBuilder._growth_rate(state, model)
	)
	economy.register_derived(&"debt_ratio", func(state: GameState, model: EconomyModel) -> float:
		return EconomyBuilder._debt_ratio(state, model)
	)

	for id in config.get("bounds", {}):
		var pair = config.get("bounds")[id]
		if pair is Array and pair.size() == 2:
			economy.set_bounds(StringName(id), float(pair[0]), float(pair[1]))
	economy.base_bounds = economy.bounds.duplicate(true)


static func _growth_rate(state: GameState, model: EconomyModel) -> float:
	var threshold := model.coefficient(state, &"debt_threshold")
	var crowding := maxf(0.0, EconomyBuilder._debt_ratio(state, model) - threshold)
	return model.coefficient(state, &"gdp_auto") \
		+ model.coefficient(state, &"gdp_conf") * (model.value(state, &"confidence") - model.coefficient(state, &"confidence_neutral")) / 100.0 \
		- model.coefficient(state, &"gdp_rate_gap") * (model.value(state, &"interest_rate") - model.coefficient(state, &"neutral_rate")) \
		- model.coefficient(state, &"gdp_tax_gap") * (model.value(state, &"tax_rate") - model.coefficient(state, &"neutral_tax")) \
		- model.coefficient(state, &"gdp_crowd") * crowding


static func _debt_ratio(state: GameState, model: EconomyModel) -> float:
	var gdp := model.value(state, &"gdp")
	if gdp == 0.0:
		return 0.0
	var ratio := model.value(state, &"debt") / gdp
	var pair: Array = model.bounds.get(&"debt_ratio", [])
	if pair.size() == 2:
		ratio = clampf(ratio, float(pair[0]), float(pair[1]))
	return ratio
