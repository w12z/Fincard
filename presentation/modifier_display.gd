class_name ModifierDisplay
extends RefCounted


# Presentation only: keep individual sources and durations intact in the simulation.
static func entries(sim: Simulation, labels: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups := {}
	var order: Array[String] = []
	var special := {}
	for modifier in sim.state.modifiers:
		if modifier.is_expired():
			continue
		if modifier.scope == Modifier.SCOPE_SPECIAL:
			var special_key := "special:%s" % modifier.target
			if not special.has(special_key):
				order.append(special_key)
				special[special_key] = modifier
			continue
		var key := "%s:%s" % [modifier.scope, modifier.target]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(modifier)
	for key in order:
		if special.has(key):
			result.append(_special_entry(sim, labels, special[key]))
			continue
		var modifiers: Array = groups[key]
		var first: Modifier = modifiers[0]
		result.append(_numeric_entry(sim, labels, first, modifiers))
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


static func _special_entry(sim: Simulation, labels: Dictionary, modifier: Modifier) -> Dictionary:
	var definition: StatusDef = sim.status_db.get(modifier.target)
	var name := definition.display_name if definition != null else String(modifier.source)
	var description := definition.description if definition != null else ""
	var icon_key := String(modifier.rule)
	var counter := StatusRules.counter(definition, sim.state) if definition != null else ""
	if modifier.rule == &"event_effects":
		var effects: Array[Effect] = []
		for raw in modifier.data.get("effects", []):
			effects.append(raw if raw is Effect else Effect.from_dict(raw))
		description = "当「%s」时：\n%s" % [TextFormatter.event_name(labels, Event.name_of(int(modifier.data.get("on_kind", -1)))), TextFormatter.effects_text(labels, effects)]
		if not effects.is_empty():
			icon_key = String(effects[0].params.get("target", "political_capital_gain"))
	var duration := "永久" if modifier.is_permanent() else "剩余%d回合" % modifier.remaining_turns
	var tooltip := "%s\n%d层 · %s\n%s" % [name, modifier.stacks, duration, description]
	if counter != "" and counter != "%d层" % modifier.stacks:
		tooltip += "\n" + counter
	if modifier.data.has("queued_card"):
		var card: CardDef = sim.card_db.get(StringName(modifier.data["queued_card"]))
		if card != null:
			tooltip += "\n待重放：" + card.display_name
	return {"key": "special:%s" % modifier.target, "name": name, "icon": icon_key, "counter": counter, "tooltip": tooltip}


static func _numeric_entry(sim: Simulation, labels: Dictionary, definition: Modifier, modifiers: Array) -> Dictionary:
	var name := TextFormatter.modifier_target(labels, definition.scope, definition.target).trim_prefix("系数·")
	var base := _base(sim, definition)
	var current := _value(sim, modifiers, base, definition)
	var tooltip := "%s\n基础值 %s\n当前合计 %s\n有效值 %s → %s" % [name, TextFormatter.fmt(base), TextFormatter.signed(current - base), TextFormatter.fmt(base), TextFormatter.fmt(current)]
	var permanent_layers := 0
	for modifier: Modifier in modifiers:
		if modifier.is_permanent():
			permanent_layers += modifier.stacks
	if permanent_layers > 0:
		tooltip += "\n永久修正 %d层" % permanent_layers
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
	return {"key": "%s:%s" % [definition.scope, definition.target], "name": name, "icon": String(definition.target), "counter": TextFormatter.signed(current - base), "value_text": TextFormatter.fmt(current), "tooltip": tooltip}


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
			Modifier.Op.ADD: value += modifier.effective_value()
			Modifier.Op.MUL: value *= modifier.effective_value()
			Modifier.Op.OVERRIDE: value = modifier.effective_value()
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
