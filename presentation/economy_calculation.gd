class_name EconomyCalculation
extends RefCounted

# Read-only presentation breakdown. Equation totals and final predictions come
# from the simulation; displayed terms never feed back into the game state.
static func branches(sim: Simulation, next: GameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if next == null:
		return result
	var model := sim.economy
	var state := sim.state
	var growth := float(model.derived[&"growth"].call(state, model))
	result.append(_growth(sim, state, "growth_now", "本次结算增长"))
	var settled := state.snapshot()
	model.tick(settled, sim.rng.snapshot())
	for id in model.indicator_ids:
		if not model.equations.has(id):
			continue
		var current := model.value(state, id)
		var future := model.value(next, id)
		var raw := float(model.equations[id].call(state, model, sim.rng.snapshot()))
		var economic := model.value(settled, id) - current
		var node := _node(String(id), _name(id), future - current, "当前 %s → 预测 %s；净变化 %s" % [_fmt(current), _fmt(future), _signed(future - current)])
		node["indicator"] = id
		node["current"] = current
		node["future"] = future
		var equation := _node("equation", "经济公式", raw, "各项均使用结算前的指标，同时计算，不将本次通胀或失业变化再次代入。")
		equation["children"] = _terms(sim, id, growth)
		# Unknown future equations still display the authoritative total.
		if equation["children"].is_empty():
			equation["children"].append(_node("raw", "公式结果", raw))
		node["children"].append(equation)
		if not is_zero_approx(economic - raw):
			node["children"].append(_node("bounds", "边界与有效值", economic - raw, "公式变化 %s；实际经济变化 %s。差额来自指标上下限及已有数值修正。" % [_signed(raw), _signed(economic)]))
		var remainder := future - current - economic
		if not is_zero_approx(remainder):
			var later := _node("later", "后续结算合计", remainder, "完整预测减去经济结算后的差额；包含内阁触发、修正到期、跨年及自动出牌等。这里不是额外的一条经济公式。")
			later["children"] = _later_sources(sim, next, id)
			node["children"].append(later)
		result.append(node)
	result.append(_resource(sim, next, &"budget"))
	result.append(_resource(sim, next, &"political_capital"))
	if next.turn > state.turn:
		result.append(_growth(sim, next, "growth_next", "下回合增长率"))
	return result


static func _terms(sim: Simulation, id: StringName, growth: float) -> Array[Dictionary]:
	var model := sim.economy
	var state := sim.state
	var target := model.coefficient(state, &"inflation_target")
	var inflation := model.value(state, &"inflation")
	var natural := model.coefficient(state, &"natural_unemployment")
	var unemployment := model.value(state, &"unemployment")
	var confidence := model.value(state, &"confidence")
	var gap := target - inflation
	var terms: Array[Dictionary] = []
	match id:
		&"gdp":
			terms.append(_term("growth", "增长带动", model.value(state, &"gdp") * growth / 100.0, "%s × %s ÷ 100" % [_fmt(model.value(state, &"gdp")), _fmt(growth)]))
		&"inflation":
			terms.append(_term("revert", "向目标回归", gap / 10.0, "(%s − %s) ÷ 10" % [_fmt(target), _fmt(inflation)]))
			terms.append(_term("growth", "增长推升物价", 1.5 * growth / 10.0, "1.5 × %s ÷ 10" % _fmt(growth)))
			var anchor := model.coefficient(state, &"infl_anchor")
			if not is_zero_approx(anchor):
				var term := _term("anchor", "额外通胀回归", anchor * gap, "%s × (%s − %s)" % [_fmt(anchor), _fmt(target), _fmt(inflation)])
				var input := _coefficient(sim, state, &"infl_anchor", "回归系数")
				input["context"] = true
				term["children"].append(input)
				terms.append(term)
		&"unemployment":
			terms.append(_term("revert", "自然水平回归", (natural - unemployment) / 10.0, "(%s − %s) ÷ 10" % [_fmt(natural), _fmt(unemployment)]))
			var divisor := 8.0 if growth > 0.0 else 2.0
			terms.append(_term("growth", "增长影响就业", -growth / divisor, "−%s ÷ %s" % [_fmt(growth), _fmt(divisor)]))
			var revert := model.coefficient(state, &"u_revert")
			if not is_zero_approx(revert):
				var term := _term("extra", "额外就业回归", -revert * maxf(unemployment - natural, 0.0), "−%s × max(%s − %s, 0)" % [_fmt(revert), _fmt(unemployment), _fmt(natural)])
				var input := _coefficient(sim, state, &"u_revert", "回归系数")
				input["context"] = true
				term["children"].append(input)
				terms.append(term)
		&"confidence":
			terms.append(_term("growth", "经济增长反馈", growth / 2.0 if growth > 0.0 else growth, "%s ÷ 2" % _fmt(growth) if growth > 0.0 else "负增长直接计入：%s" % _fmt(growth)))
			terms.append(_term("prices", "物价偏离惩罚", -absf(inflation - target) / 5.0, "−|%s − %s| ÷ 5" % [_fmt(inflation), _fmt(target)]))
			terms.append(_term("jobs", "高失业惩罚", -maxf(unemployment - natural, 0.0) / 5.0, "−max(%s − %s, 0) ÷ 5" % [_fmt(unemployment), _fmt(natural)]))
			terms.append(_term("low", "低信心螺旋", -maxf(50.0 - confidence, 0.0) * 0.05, "−max(50 − %s, 0) × 0.05" % _fmt(confidence)))
			if state.budget < 0:
				terms.append(_term("deficit", "赤字惩罚", state.budget / 5.0, "−%s ÷ 5" % absi(state.budget)))
			# Evaluate each special modifier using the same economic rule, rather
			# than reproducing cap, expiry, and stage-specific crash arithmetic.
			for index in state.modifiers.size():
				var modifier: Modifier = state.modifiers[index]
				if modifier.rule not in [&"growth_confidence_bonus", &"negative_growth_confidence"] or not modifier.is_active(state.turn):
					continue
				var isolated := state.snapshot()
				isolated.modifiers.assign([modifier.snapshot()])
				var delta := EconomyBuilder.special_confidence_delta(isolated, growth)
				var definition: StatusDef = sim.status_db.get(modifier.target)
				var term := _node("special_%d" % index, definition.display_name if definition != null else String(modifier.source), delta, definition.description if definition != null else "")
				terms.append(term)
	return terms


static func _growth(sim: Simulation, state: GameState, key: String, title: String) -> Dictionary:
	var model := sim.economy
	var rate := float(model.derived[&"growth"].call(state, model))
	var node := _node(key, title, rate, "潜在增长 + 信心÷100 − 利率÷10 − 物价拖累。所有数值均为百分点。")
	node["suffix"] = "%"
	node["expanded"] = key == "growth_now"
	var potential := _coefficient(sim, state, &"gdp_auto", "潜在增长")
	node["children"].append(potential)
	var confidence := model.value(state, &"confidence")
	node["children"].append(_term("confidence", "信心推动", confidence / 100.0, "%s ÷ 100" % _fmt(confidence)))
	var interest := model.value(state, &"interest_rate")
	var rate_term := _term("interest", "利率拖累", -interest / 10.0, "−%s ÷ 10" % _fmt(interest))
	var rate_input := _sources(sim, state, Modifier.SCOPE_INDICATOR, &"interest_rate", "有效利率", float(state.indicators.get(&"interest_rate", 0)), interest)
	rate_input["context"] = true
	rate_term["children"].append(rate_input)
	node["children"].append(rate_term)
	var inflation := model.value(state, &"inflation")
	var target := model.coefficient(state, &"inflation_target")
	var drag := EconomyBuilder.inflation_growth_drag(state, model)
	var price := _node("prices", "物价拖累", -drag, "温和区间 %s%%～%s%%；超上限每点拖累0.15，低于下限每点拖累0.20。" % [_fmt(target - 2), _fmt(target + 2)])
	price["children"].append(_term("high", "高通胀部分", -maxf(inflation - target - 2, 0) * 0.15, "−max(%s − %s, 0) × 0.15" % [_fmt(inflation), _fmt(target + 2)]))
	price["children"].append(_term("low", "通缩部分", -maxf(target - 2 - inflation, 0) * 0.20, "−max(%s − %s, 0) × 0.20" % [_fmt(target - 2), _fmt(inflation)]))
	node["children"].append(price)
	var raw := float(potential["value"]) + confidence / 100.0 - interest / 10.0 - drag
	if not is_zero_approx(rate - raw):
		node["children"].append(_node("bounds", "增长率边界", rate - raw, "将增长率限制在当前规则允许的区间内。"))
	return node


static func _coefficient(sim: Simulation, state: GameState, id: StringName, title: String) -> Dictionary:
	var base := float(sim.economy.scenario_coefficients.get(id, sim.economy.base_coefficients.get(id, 0.0)))
	return _sources(sim, state, Modifier.SCOPE_COEFFICIENT, id, title, base, sim.economy.coefficient(state, id))


static func _sources(_sim: Simulation, state: GameState, scope: StringName, id: StringName, title: String, base: float, total: float) -> Dictionary:
	var node := _node(String(id), title, total, "按修正列表的先后顺序依次运算；合计采用游戏当前有效值。")
	node["signed"] = false
	node["children"].append(_node("base", "基础值", base))
	var running := base
	for index in state.modifiers.size():
		var modifier: Modifier = state.modifiers[index]
		if modifier.scope != scope or modifier.target != id or modifier.is_expired():
			continue
		var previous := running
		match modifier.op:
			Modifier.Op.ADD: running += modifier.effective_value()
			Modifier.Op.MUL: running *= modifier.effective_value()
			Modifier.Op.OVERRIDE: running = modifier.effective_value()
		var duration := "永久" if modifier.is_permanent() else "剩余%d回合" % modifier.remaining_turns
		node["children"].append(_node("source_%d" % index, String(modifier.source) if modifier.source != &"" else "数值修正", running - previous, "%s；%s %s；%s → %s" % [duration, Modifier.op_label(modifier.op), _fmt(modifier.effective_value()), _fmt(previous), _fmt(running)]))
	if not is_zero_approx(total - running):
		node["children"].append(_node("bounds", "有效值边界", total - running))
	return node


static func _resource(sim: Simulation, next: GameState, id: StringName) -> Dictionary:
	var budget := id == &"budget"
	var current := sim.state.budget if budget else sim.state.political_capital
	var future := next.budget if budget else next.political_capital
	var node := _node(String(id), "预算" if budget else "政治点", future - current, "当前 %d → 预测 %d" % [current, future])
	node["indicator"] = id
	node["current"] = float(current)
	node["future"] = float(future)
	var explained := 0.0
	if next.turn > sim.state.turn:
		if budget and next.year > sim.state.year:
			var carried := current if current < 0 else int(floor(current * sim.budget_retention()))
			node["children"].append(_term("retention", "跨年结转损耗", carried - current, "%d → %d；保留系数 %s" % [current, carried, _fmt(sim.budget_retention())]))
			var income := _sources(sim, sim.state, Modifier.SCOPE_FISCAL, &"annual_income", "年度预算收入", sim.state.base_annual_income, sim.annual_income())
			node["children"].append(income)
			explained = carried - current + sim.annual_income()
		elif not budget:
			var reset := sim.political_capital_per_turn()
			node["children"].append(_term("reset", "每回合重置", reset - current, "%d → %d；未花完的政治点不自动累积。" % [current, reset]))
			explained = reset - current
	if not is_zero_approx(future - current - explained):
		var later := _node("later", "触发及其他变化", future - current - explained, "完整预测中除已列出的结转、收入或政治点重置以外的净变化，包含储备返还、内阁与自动出牌。")
		later["children"] = _later_sources(sim, next, id)
		node["children"].append(later)
	return node


static func _later_sources(sim: Simulation, next: GameState, target: StringName) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	# These are context, not separately attributed numeric contributions. The
	# aggregate includes interactions, caps, and sequential percentage effects.
	for cabinet: CabinetDef in sim.state.cabinets:
		for index in cabinet.triggers.size():
			var trigger: Trigger = cabinet.triggers[index]
			if not _affects(trigger.effects, target):
				continue
			if trigger.on_kind == Event.Kind.TURN_ENDED or (next.turn > sim.state.turn and trigger.on_kind == Event.Kind.TURN_STARTED) or (next.year > sim.state.year and trigger.on_kind == Event.Kind.YEAR_STARTED):
				var node := _node("cabinet_%s_%d" % [cabinet.id, index], cabinet.display_name, 0, cabinet.description)
				node["context"] = true
				node["text"] = "触发"
				nodes.append(node)
	for index in sim.state.modifiers.size():
		var modifier: Modifier = sim.state.modifiers[index]
		if modifier.remaining_turns == 1 and modifier.scope == Modifier.SCOPE_INDICATOR and modifier.target == target:
			var node := _node("expiry_%d" % index, String(modifier.source), 0, "本次回合结束后，限期修正到期；不代表立即反向扣除其原有效果。")
			node["context"] = true
			node["text"] = "到期"
			nodes.append(node)
		if next.turn > sim.state.turn and modifier.rule in [&"next_turn_replay", &"last_card_next_turn"] and (modifier.data.has("queued_card") or (modifier.rule == &"last_card_next_turn" and not sim.state.played_cards_this_turn.is_empty())):
			var id := StringName(modifier.data.get("queued_card", ""))
			if modifier.rule == &"last_card_next_turn" and not sim.state.played_cards_this_turn.is_empty():
				id = sim.state.played_cards_this_turn.back()
			var card: CardDef = sim.card_db.get(id)
			if card != null:
				var node := _node("auto_%d" % index, card.display_name, 0, "本次预测中的自动出牌：效果及相关触发已计入完整预测，不作为一笔独立数值再次相加。")
				node["context"] = true
				node["text"] = "自动"
				nodes.append(node)
	return nodes


static func _affects(effects: Array[Effect], target: StringName) -> bool:
	for effect in effects:
		if effect.kind in [Effect.Kind.ADJUST_INDICATOR, Effect.Kind.APPLY_MODIFIER] and StringName(effect.params.get("target", "")) == target:
			return true
		if (effect.kind == Effect.Kind.GAIN_BUDGET and target == &"budget") or (effect.kind == Effect.Kind.GAIN_POLITICAL_CAPITAL and target == &"political_capital"):
			return true
	return false


static func _term(key: String, title: String, value: float, formula: String) -> Dictionary:
	var node := _node(key, title, value, formula + " = " + _signed(value))
	var input := _node("formula", formula, value, node["tooltip"])
	input["context"] = true
	input["text"] = "代入"
	node["children"].append(input)
	return node


static func _node(key: String, title: String, value: float, tooltip: String = "") -> Dictionary:
	return {"key": key, "title": title, "value": value, "tooltip": tooltip, "children": [], "signed": true, "expanded": false}


static func _name(id: StringName) -> String:
	return {&"gdp": "GDP", &"inflation": "通胀", &"unemployment": "失业率", &"confidence": "信心"}.get(id, String(id))


static func _fmt(value: float) -> String:
	return TextFormatter.fmt(value)


static func _signed(value: float) -> String:
	return TextFormatter.signed(value)
