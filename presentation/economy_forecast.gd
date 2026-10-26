class_name EconomyForecast
extends RefCounted


static func text(sim: Simulation, labels: Dictionary) -> String:
	var next := sim.forecast_next_turn()
	if next == null:
		return "待完成当前选择" if sim.state.run_status == GameState.RunStatus.RUNNING else "本局已结束"
	var parts := PackedStringArray(["[b]下回合预测[/b]", "[color=#667085]不含事件及新增奖励[/color]"])
	for id in sim.economy.indicator_ids + sim.economy.derived_ids:
		var current := sim.economy.value(sim.state, id)
		var future := sim.economy.value(next, id)
		parts.append("%s  %s → %s（%s）" % [TextFormatter.indicator(labels, id), TextFormatter.fmt(current), TextFormatter.fmt(future), TextFormatter.signed(future - current)])
	parts.append("预算  %d → %d" % [sim.state.budget, next.budget])
	parts.append("政治点  %d → %d" % [sim.state.political_capital, next.political_capital])
	if next.run_status != GameState.RunStatus.RUNNING:
		parts.append("本次结算：%s" % ("目标达成" if next.run_status == GameState.RunStatus.WON else "计划失败"))
	parts.append("\n[b]本次经济结算[/b]")
	parts.append(formulas(sim))
	return "\n".join(parts)


static func formulas(sim: Simulation) -> String:
	var c := func(id: StringName) -> String: return TextFormatter.fmt(sim.economy.coefficient(sim.state, id))
	var v := func(id: StringName) -> String: return TextFormatter.fmt(sim.economy.value(sim.state, id))
	var growth := float(sim.economy.derived[&"growth"].call(sim.state, sim.economy))
	var g := TextFormatter.fmt(growth)
	var parts := PackedStringArray()
	parts.append("月增长率 = %s + %s / 100 − %s / 10 = %s%%" % [c.call(&"gdp_auto"), v.call(&"confidence"), v.call(&"interest_rate"), g])
	parts.append("ΔGDP = %s × %s / 100" % [v.call(&"gdp"), g])
	var inflation := "Δ通胀 = (%s − %s + %s) / 10" % [c.call(&"inflation_target"), v.call(&"inflation"), g]
	if not is_zero_approx(sim.economy.coefficient(sim.state, &"infl_anchor")):
		inflation += " + %s × (%s − %s)" % [c.call(&"infl_anchor"), c.call(&"inflation_target"), v.call(&"inflation")]
	parts.append(inflation)
	var unemployment := "Δ失业率 = (%s − %s) / 10 − %s / 2" % [c.call(&"natural_unemployment"), v.call(&"unemployment"), g]
	if not is_zero_approx(sim.economy.coefficient(sim.state, &"u_revert")):
		unemployment += " + %s × (%s − %s)" % [c.call(&"u_revert"), c.call(&"natural_unemployment"), v.call(&"unemployment")]
	parts.append(unemployment)
	parts.append("Δ信心 = %s − |%s − %s| / 10" % [g, v.call(&"inflation"), c.call(&"inflation_target")])
	# Equation results come from the same callables as the simulation, not a
	# second implementation of the economy's arithmetic.
	for id in sim.economy.indicator_ids:
		if sim.economy.equations.has(id):
			var delta := float(sim.economy.equations[id].call(sim.state, sim.economy, sim.rng.snapshot()))
			parts.append("Δ%s = %s" % [_indicator_name(id), TextFormatter.signed(delta)])
	return "\n".join(parts)


static func _indicator_name(id: StringName) -> String:
	return {&"gdp": "GDP", &"inflation": "通胀", &"unemployment": "失业率", &"confidence": "信心"}.get(id, String(id))


static func parameters(sim: Simulation, labels: Dictionary) -> String:
	var parts := PackedStringArray(["[b]规则[/b]"])
	var names := {
		"draw_per_turn": "每回合抽牌", "turns_per_year": "每财年回合",
		"reward_option_count": "每组奖励候选", "card_reward_groups": "卡牌奖励组数",
		"political_capital_per_turn": "每回合政治点重置基础值", "random_event_chance": "随机事件概率",
		"budget_retention": "基础预算结转系数",
		"trigger_iteration_limit": "连锁结算上限",
	}
	for key in names:
		parts.append("%s：%s" % [names[key], TextFormatter.fmt(float(sim.rules.get(key, 0)))])
	parts.append("\n[b]数值边界[/b]")
	for id in sim.economy.bounds:
		var pair: Array = sim.economy.bounds[id]
		parts.append("%s：%s ～ %s" % [TextFormatter.indicator(labels, id), TextFormatter.fmt(pair[0]), TextFormatter.fmt(pair[1])])
	return "\n".join(parts)
