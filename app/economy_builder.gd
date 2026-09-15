class_name EconomyBuilder
extends RefCounted


static func build(economy: EconomyModel, config: Dictionary) -> void:
	var c: Dictionary = config.get("coefficients", {})
	var natural_unemployment := float(c.get("natural_unemployment", 0.0))
	var neutral_rate := float(c.get("neutral_rate", 0.0))
	var debt_threshold := float(c.get("debt_threshold", 0.0))
	var confidence_neutral := float(c.get("confidence_neutral", 0.0))

	economy.equations[&"gdp"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var rate_gap := model.value(state, &"interest_rate") - neutral_rate
		var crowding := maxf(0.0, EconomyBuilder._debt_ratio(state, model) - debt_threshold)
		var confidence_gap := model.value(state, &"confidence") - confidence_neutral
		return float(c.get("gdp_autonomy", 0.0)) \
			+ float(c.get("gdp_confidence", 0.0)) * confidence_gap \
			- float(c.get("gdp_rate", 0.0)) * rate_gap \
			- float(c.get("gdp_crowding", 0.0)) * crowding \
			- float(c.get("gdp_tax", 0.0)) * model.value(state, &"tax_rate") \
			+ float(c.get("gdp_budget", 0.0)) * state.budget_scale

	economy.equations[&"inflation"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var rate_gap := model.value(state, &"interest_rate") - neutral_rate
		return float(c.get("inflation_persistence", 0.0)) * model.value(state, &"inflation") \
			+ float(c.get("inflation_phillips", 0.0)) * (natural_unemployment - model.value(state, &"unemployment")) \
			+ float(c.get("inflation_overheat", 0.0)) * EconomyBuilder._growth(state) \
			+ float(c.get("inflation_budget", 0.0)) * state.budget_scale \
			- float(c.get("inflation_rate", 0.0)) * rate_gap

	economy.equations[&"unemployment"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		return float(c.get("unemployment_okun", 0.0)) * (-EconomyBuilder._growth(state)) \
			+ float(c.get("unemployment_reversion", 0.0)) * (natural_unemployment - model.value(state, &"unemployment"))

	economy.equations[&"debt"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var debt := model.value(state, &"debt")
		var gdp := model.value(state, &"gdp")
		return float(c.get("debt_spending", 0.0)) * state.budget_scale \
			- float(c.get("debt_revenue", 0.0)) * model.value(state, &"tax_rate") * gdp \
			+ float(c.get("debt_interest", 0.0)) * debt * model.value(state, &"interest_rate")

	economy.equations[&"confidence"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		var crowding := maxf(0.0, EconomyBuilder._debt_ratio(state, model) - debt_threshold)
		return float(c.get("confidence_growth", 0.0)) * EconomyBuilder._growth(state) \
			- float(c.get("confidence_inflation", 0.0)) * model.value(state, &"inflation") \
			- float(c.get("confidence_debt", 0.0)) * crowding \
			+ float(c.get("confidence_budget", 0.0)) * state.budget_scale \
			+ float(c.get("confidence_reversion", 0.0)) * (confidence_neutral - model.value(state, &"confidence"))

	economy.equations[&"approval"] = func(state: GameState, model: EconomyModel, _rng: Rng) -> float:
		return float(c.get("approval_growth", 0.0)) * EconomyBuilder._growth(state) \
			- float(c.get("approval_inflation", 0.0)) * model.value(state, &"inflation") \
			- float(c.get("approval_unemployment", 0.0)) * model.value(state, &"unemployment") \
			- float(c.get("approval_debt", 0.0)) * EconomyBuilder._debt_ratio(state, model)

	economy.register_derived(&"growth", func(state: GameState, _model: EconomyModel) -> float:
		return EconomyBuilder._growth(state)
	)
	economy.register_derived(&"debt_ratio", func(state: GameState, model: EconomyModel) -> float:
		return EconomyBuilder._debt_ratio(state, model)
	)


static func _growth(state: GameState) -> float:
	var previous := float(state.prev_indicators.get(&"gdp", 0.0))
	if previous == 0.0:
		return 0.0
	return (float(state.indicators.get(&"gdp", 0.0)) - previous) / previous


static func _debt_ratio(state: GameState, economy: EconomyModel) -> float:
	var gdp := economy.value(state, &"gdp")
	if gdp == 0.0:
		return 0.0
	return economy.value(state, &"debt") / gdp
