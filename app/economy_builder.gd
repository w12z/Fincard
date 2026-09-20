class_name EconomyBuilder
extends RefCounted


static func build(economy: EconomyModel, config: Dictionary, rules: Dictionary) -> void:
	var c: Dictionary = config.get("coefficients", {})
	var u_natural := float(c.get("natural_unemployment", 0.0))
	var rate_neutral := float(c.get("neutral_rate", 0.0))
	var tax_neutral := float(c.get("neutral_tax", 0.0))
	var ratio_threshold := float(c.get("debt_threshold", 0.0))
	var conf_neutral := float(c.get("confidence_neutral", 0.0))
	var infl_target := float(c.get("inflation_target", 0.0))

	economy.equations[&"gdp"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var gdp := model.value(state, &"gdp")
		var g_rate := EconomyBuilder._growth_rate(state, model, c, u_natural, rate_neutral, tax_neutral, ratio_threshold, conf_neutral)
		return gdp * g_rate / 100.0

	economy.equations[&"inflation"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var g_rate := model.value(state, &"growth")
		return float(c.get("infl_anchor", 0.0)) * (infl_target - model.value(state, &"inflation")) \
			+ float(c.get("infl_phillips", 0.0)) * (u_natural - model.value(state, &"unemployment")) \
			+ float(c.get("infl_demand", 0.0)) * g_rate \
			+ float(c.get("infl_stim", 0.0)) * state.budget_scale \
			- float(c.get("infl_rate", 0.0)) * (model.value(state, &"interest_rate") - rate_neutral)

	economy.equations[&"unemployment"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		return float(c.get("u_revert", 0.0)) * (u_natural - model.value(state, &"unemployment")) \
			- float(c.get("u_okun", 0.0)) * model.value(state, &"growth")

	economy.equations[&"debt"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var gdp := model.value(state, &"gdp")
		var ratio := EconomyBuilder._debt_ratio(state, model)
		var stimulus := float(c.get("debt_spend", 0.0)) * state.budget_scale
		var revenue := float(c.get("debt_rev", 0.0)) * (model.value(state, &"tax_rate") / 100.0)
		var burden := float(c.get("debt_int_pass", 0.0)) * ratio * (model.value(state, &"interest_rate") / 100.0)
		return gdp * (stimulus - revenue + burden)

	economy.equations[&"confidence"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var crowding := maxf(0.0, EconomyBuilder._debt_ratio(state, model) - ratio_threshold)
		return float(c.get("conf_growth", 0.0)) * model.value(state, &"growth") \
			- float(c.get("conf_infl", 0.0)) * model.value(state, &"inflation") \
			- float(c.get("conf_debt", 0.0)) * crowding \
			+ float(c.get("conf_stim", 0.0)) * state.budget_scale \
			+ float(c.get("conf_anchor", 0.0)) * (conf_neutral - model.value(state, &"confidence"))

	economy.equations[&"approval"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		return float(c.get("appr_growth", 0.0)) * model.value(state, &"growth") \
			- float(c.get("appr_infl", 0.0)) * maxf(0.0, model.value(state, &"inflation")) \
			- float(c.get("appr_u", 0.0)) * model.value(state, &"unemployment") \
			- float(c.get("appr_debt", 0.0)) * EconomyBuilder._debt_ratio(state, model) \
			+ float(c.get("appr_anchor", 0.0)) * (conf_neutral - model.value(state, &"approval"))

	economy.register_derived(&"growth", func(state: GameState, model: EconomyModel) -> float:
		return EconomyBuilder._growth_rate(state, model, c, u_natural, rate_neutral, tax_neutral, ratio_threshold, conf_neutral)
	)
	economy.register_derived(&"debt_ratio", func(state: GameState, model: EconomyModel) -> float:
		return EconomyBuilder._debt_ratio(state, model)
	)

	for id in config.get("bounds", {}):
		var pair = config.get("bounds")[id]
		if pair is Array and pair.size() == 2:
			economy.set_bounds(StringName(id), float(pair[0]), float(pair[1]))


static func _growth_rate(state: GameState, model: EconomyModel, c: Dictionary, u_natural: float, rate_neutral: float, tax_neutral: float, ratio_threshold: float, conf_neutral: float) -> float:
	var crowding := maxf(0.0, EconomyBuilder._debt_ratio(state, model) - ratio_threshold)
	return float(c.get("gdp_auto", 0.0)) \
		+ float(c.get("gdp_conf", 0.0)) * (model.value(state, &"confidence") - conf_neutral) / 100.0 \
		- float(c.get("gdp_rate_gap", 0.0)) * (model.value(state, &"interest_rate") - rate_neutral) \
		- float(c.get("gdp_tax_gap", 0.0)) * (model.value(state, &"tax_rate") - tax_neutral) \
		- float(c.get("gdp_crowd", 0.0)) * crowding \
		+ float(c.get("gdp_stim", 0.0)) * state.budget_scale


static func _debt_ratio(state: GameState, model: EconomyModel) -> float:
	var gdp := model.value(state, &"gdp")
	if gdp == 0.0:
		return 0.0
	return model.value(state, &"debt") / gdp
