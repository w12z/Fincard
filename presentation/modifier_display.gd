class_name ModifierDisplay
extends RefCounted


# Presentation only: keep individual sources and durations intact in the simulation.
static func entries(sim: Simulation, labels: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups := {}
	for modifier in sim.state.modifiers:
		if modifier.is_expired():
			continue
		var key := "%s:%s" % [modifier.scope, modifier.target]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(modifier)
	for key in groups:
		var modifiers: Array = groups[key]
		var first: Modifier = modifiers[0]
		result.append(_numeric_entry(sim, labels, first, modifiers))
	var rules := {}
	for id in sim.state.statuses:
		var status: StatusDef = sim.status_db.get(id)
		if status == null or rules.has(status.rule):
			continue
		rules[status.rule] = true
		result.append({"key": "status:%s" % status.rule, "name": status.display_name, "icon": status.icon, "counter": StatusRules.counter(status, sim.state), "tooltip": "%s · 永久\n%s\n%s" % [status.display_name, status.description, StatusRules.progress(status, sim.state)]})
	# Unmodified parameters are still visible, without creating simulation modifiers.
	var coefficients := sim.economy.base_coefficients.duplicate()
	coefficients.merge(sim.economy.scenario_coefficients, true)
	var defaults: Array[Modifier] = []
	for target in coefficients:
		defaults.append(Modifier.new(StringName(target), Modifier.Op.ADD, 0, -1, &"", Modifier.SCOPE_COEFFICIENT))
	for definition in defaults:
		if not groups.has("%s:%s" % [definition.scope, definition.target]):
			result.append(_numeric_entry(sim, labels, definition, []))
	return result


static func _numeric_entry(sim: Simulation, labels: Dictionary, definition: Modifier, modifiers: Array) -> Dictionary:
	var name := TextFormatter.modifier_target(labels, definition.scope, definition.target).trim_prefix("系数·")
	var base := _base(sim, definition)
	var current := _value(sim, modifiers, base, definition)
	var tooltip := "%s\n基础值 %s\n当前合计 %s\n有效值 %s → %s" % [name, TextFormatter.fmt(base), TextFormatter.signed(current - base), TextFormatter.fmt(base), TextFormatter.fmt(current)]
	var deadlines: Array[int] = []
	for modifier: Modifier in modifiers:
		if not modifier.is_permanent() and not deadlines.has(modifier.remaining_turns):
			deadlines.append(modifier.remaining_turns)
	deadlines.sort()
	for deadline in deadlines:
		var remaining: Array = []
		for modifier: Modifier in modifiers:
			if modifier.is_permanent() or modifier.remaining_turns > deadline:
				remaining.append(modifier)
		var future := _value(sim, remaining, base, definition)
		var unit := "次财年发放后" if definition.scope == Modifier.SCOPE_FISCAL else "回合后"
		tooltip += "\n%d %s：合计 %s · 有效值 %s" % [deadline, unit, TextFormatter.signed(future - base), TextFormatter.fmt(future)]
	if deadlines.is_empty():
		tooltip += "\n永久"
	return {"key": "%s:%s" % [definition.scope, definition.target], "name": name, "icon": name.left(2), "counter": TextFormatter.signed(current - base), "value_text": TextFormatter.fmt(current), "tooltip": tooltip}


static func _base(sim: Simulation, modifier: Modifier) -> float:
	match modifier.scope:
		Modifier.SCOPE_REWARD:
			return sim.base_rarity_weight(modifier.target)
		Modifier.SCOPE_COEFFICIENT:
			return float(sim.economy.scenario_coefficients.get(modifier.target, sim.economy.base_coefficients.get(modifier.target, 0.0)))
		Modifier.SCOPE_FISCAL:
			return sim.state.base_annual_income if modifier.target == &"annual_income" else sim.state.base_budget_retention
	return float(sim.state.indicators.get(modifier.target, 0.0))


static func _value(sim: Simulation, modifiers: Array, base: float, definition: Modifier = null) -> float:
	var value := base
	for modifier: Modifier in modifiers:
		definition = modifier
		match modifier.op:
			Modifier.Op.ADD: value += modifier.value
			Modifier.Op.MUL: value *= modifier.value
			Modifier.Op.OVERRIDE: value = modifier.value
	if definition == null:
		return value
	if definition.scope == Modifier.SCOPE_INDICATOR:
		var bounds: Array = sim.economy.bounds.get(definition.target, [])
		if bounds.size() == 2:
			value = clampf(value, float(bounds[0]), float(bounds[1]))
	elif definition.scope == Modifier.SCOPE_FISCAL:
		value = maxf(0, floorf(value)) if definition.target == &"annual_income" else clampf(value, 0, 1)
	elif definition.scope == Modifier.SCOPE_REWARD:
		value = maxf(0, value)
	return value
