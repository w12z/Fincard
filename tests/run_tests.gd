extends SceneTree

var controller: GameController
var failures: int = 0
const REMOVED_FIELDS := ["debt", "debt_ratio", "tax_rate", "neutral_tax", "debt_threshold", "gdp_tax_gap", "gdp_crowd", "debt_spend", "debt_rev", "debt_int_pass", "conf_debt"]


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _new_run(scenario: StringName, seed_value: int = 1) -> Simulation:
	controller.simulation.rng = Rng.new(seed_value)
	controller.simulation.state.seed_value = seed_value
	controller.simulation.start_run(scenario)
	return controller.simulation


func _setup(sim: Simulation) -> void:
	sim.apply_command(Command.choose_reward([]))
	if sim.state.pending_event != &"":
		sim.apply_command(Command.resolve_event(0))


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 1
	root.add_child(controller)
	_test_content()
	_test_rules()
	_test_economy()
	_test_indicator_reset()
	_test_reward_pool_resolution()
	await _test_ui()
	var sample_count := 100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			sample_count = maxi(1, int(arg.trim_prefix("--seeds=")))
	for scenario in [&"example_country", &"arcadia"]:
		for policy in ["passive", "random", "planned"]:
			var wins := 0
			var turns := 0
			var min_turn := 1000
			var max_turn := 0
			for seed_value in range(1, sample_count + 1):
				var result := _autoplay(scenario, seed_value, policy)
				if not result["won"] and policy == "planned" and "--diagnostics" in OS.get_cmdline_user_args():
					print("PLANNED LOSS %s seed=%d reason=%s indicators=%s" % [scenario, seed_value, controller.simulation.state.flags.get("loss_reason", ""), controller.simulation.state.indicators])
				wins += int(result["won"])
				turns += int(result["turn"])
				if result["won"]:
					min_turn = mini(min_turn, result["turn"])
					max_turn = maxi(max_turn, result["turn"])
			print("BALANCE %s %s wins=%d/%d mean_turn=%.1f win_turns=%d..%d" % [scenario, policy, wins, sample_count, float(turns) / sample_count, min_turn, max_turn])
			if policy == "passive":
				_expect(wins == 0, "Passive play must not win: %s" % scenario)
			if policy == "planned":
				_expect(wins >= sample_count * (0.9 if scenario == &"example_country" else 0.65), "Planned play win rate too low: %s" % scenario)
	print("TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	controller.free()
	quit(0 if failures == 0 else 1)


func _test_content() -> void:
	_check_economic_data_dir("res://data")
	var databases := {"cards": controller.cards, "events": controller.events, "cabinets": controller.cabinets, "aids": controller.aids}
	for group in controller.groups.values():
		for id in group.members:
			_expect(databases[String(group.type)].has(id), "Missing group member %s" % id)
	for scenario in controller.scenarios.values():
		for id in scenario.starting_deck:
			_expect(controller.cards.has(id), "Missing starter %s" % id)
		for id in scenario.event_pool:
			_expect(controller.events.has(id), "Missing event %s" % id)
		for id in scenario.scheduled_events.values():
			_expect(controller.events.has(id), "Missing scheduled event %s" % id)
		_expect(scenario.annual_income > 0, "Countries require annual income")
		for ids in scenario.groups.values():
			for id in ids:
				_expect(controller.groups.has(id), "Missing scenario group %s" % id)
	_expect(controller.events.size() == 19, "All 19 events must load without duplicate IDs")
	_expect(controller.cards.size() == 34, "All 34 cards must load")
	_expect(controller.statuses.size() == 4, "All special abilities must load")
	for card: CardDef in controller.cards.values():
		_expect(CardDef.RARITIES.has(card.rarity), "Card must have a supported rarity: %s" % card.id)
		_expect(_card_effect_count(card.effects) <= 2, "Card exceeds two effects (including conditional branches): %s" % card.id)
		_expect(_card_effect_targets(card.effects).size() <= 2, "Card exceeds two effect types across all branches: %s" % card.id)
		for effect: Effect in card.effects:
			if effect.kind == Effect.Kind.GRANT_STATUS:
				_expect(controller.statuses.has(StringName(effect.params.get("status", ""))), "Ability card must reference an existing status")
	for status: StatusDef in controller.statuses.values():
		_expect(status.rule in [&"first_card_political_free", &"first_investment_discount", &"third_card_draw", &"deficit_spending"], "Status must have an implemented rule")


func _check_economic_data_dir(path: String) -> void:
	for directory in DirAccess.get_directories_at(path):
		_check_economic_data_dir(path.path_join(directory))
	for filename in DirAccess.get_files_at(path):
		if filename.ends_with(".json"):
			var file_path := path.path_join(filename)
			var data = JSON.parse_string(FileAccess.get_file_as_string(file_path))
			_expect(data != null, "Invalid JSON: %s" % file_path)
			_check_economic_data(data, file_path)


func _check_economic_data(data: Variant, path: String) -> void:
	if data is Dictionary:
		for key in data:
			_expect(not REMOVED_FIELDS.has(String(key)), "Removed economic field in %s: %s" % [path, key])
			_check_economic_data(data[key], path)
		if data.has("target"):
			var labels: Dictionary = controller.labels["coefficients"] if data.get("scope", "indicator") == "coefficient" else controller.labels["indicators"]
			if data.get("scope", "indicator") == "fiscal":
				labels = controller.labels["fiscal"]
			if data.get("scope", "indicator") == "reward":
				labels = controller.labels["reward"]
			_expect(labels.has(data["target"]), "Unknown effect target in %s: %s" % [path, data["target"]])
		if data.has("indicator"):
			_expect(controller.labels["indicators"].has(data["indicator"]), "Unknown condition indicator in %s" % path)
		if data.get("kind", "") == "gain_card":
			_expect(controller.cards.has(StringName(data.get("params", {}).get("card", ""))), "Granted card must exist: %s" % path)
	elif data is Array:
		for value in data:
			_check_economic_data(value, path)
	elif data is String:
		_expect(not REMOVED_FIELDS.has(data), "Removed economic reference in %s: %s" % [path, data])


func _card_effect_count(effects: Array) -> int:
	var count := 0
	for effect: Effect in effects:
		if effect.kind == Effect.Kind.BRANCH:
			count += maxi(_card_effect_count(TextFormatter.parse_effects(effect.params.get("then", []))), _card_effect_count(TextFormatter.parse_effects(effect.params.get("else", []))))
		else:
			# Count abilities and protections too: wrappers must not hide extra effects.
			count += 1
	return count


func _card_effect_targets(effects: Array) -> Dictionary:
	var targets := {}
	for effect: Effect in effects:
		if effect.kind == Effect.Kind.BRANCH:
			for branch in ["then", "else"]:
				targets.merge(_card_effect_targets(TextFormatter.parse_effects(effect.params.get(branch, []))))
		elif effect.kind in [Effect.Kind.ADJUST_INDICATOR, Effect.Kind.APPLY_MODIFIER, Effect.Kind.REMOVE_MODIFIER]:
			targets["%s:%s" % [effect.params.get("scope", "indicator"), effect.params.get("target", "")]] = true
		elif effect.kind == Effect.Kind.GRANT_STATUS:
			targets["status:%s" % effect.params.get("status", "")] = true
		else:
			targets["kind:%d" % effect.kind] = true
	return targets


func _test_rules() -> void:
	var sim := _new_run(&"arcadia")
	var original := sim.state.budget
	_expect(sim.apply_command(Command.end_turn()).is_empty(), "Cannot end turn during opening setup")
	_expect(sim.state.turn == 0 and sim.state.budget == original, "Rejected command mutated state")
	_setup(sim)
	# An event must block both cards and aid, even if MAIN is the current phase.
	sim._fire_event(&"arcadia_ev_bank_run")
	sim.state.hand.assign([&"arcadia_relief_ccc"])
	sim.state.budget = 20
	sim.state.political_capital = 20
	_expect(sim.apply_command(Command.play_card(&"arcadia_relief_ccc")).is_empty(), "Cannot play during event")
	sim._gain_aid(&"arcadia_aid_fireside")
	_expect(sim.apply_command(Command.use_aid(&"arcadia_aid_fireside")).is_empty(), "Cannot use aid during event")
	sim.apply_command(Command.resolve_event(0))
	sim.state.hand.assign([&"arcadia_recover_sec", &"arcadia_recover_sec"])
	sim.state.deck.append(&"arcadia_recover_sec")
	sim.apply_command(Command.play_card(&"arcadia_recover_sec"))
	_expect(not sim.state.hand.has(&"arcadia_recover_sec") and not sim.state.deck.has(&"arcadia_recover_sec"), "Law must remove all copies")
	_expect(not sim._reward_available(Reward.Type.CARD, &"arcadia_recover_sec"), "Enacted law must not return as reward")
	sim.state.deck.append(&"arcadia_recover_fdic")
	_expect(not sim._reward_available(Reward.Type.CARD, &"arcadia_recover_fdic"), "Owned law must not duplicate in rewards")
	# Duration 1 lasts for exactly the current settlement.
	sim.state.modifiers.clear()
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {"target": "interest_rate", "op": "add", "value": -100, "duration": 1}}), sim.state, sim.rng)
	_expect(sim.economy.value(sim.state, &"interest_rate") == 0, "Effective values must respect bounds")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.modifiers.is_empty(), "One-turn modifier must expire")
	# Cabinet turn-end effects must happen before goals, not next month.
	sim = _new_run(&"example_country")
	_setup(sim)
	sim.state.turn = 13
	sim.state.indicators[&"gdp"] = 135.01
	sim.state.indicators[&"unemployment"] = 6.1
	sim.state.indicators[&"inflation"] = 2
	sim.economy.scenario_coefficients[&"gdp_auto"] = 0
	sim.state.indicators[&"confidence"] = 50
	sim.state.indicators[&"interest_rate"] = 5
	sim._appoint_cabinet(&"arcadia_cab_labor")
	sim._appoint_cabinet(&"arcadia_cab_interior")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.run_status == GameState.RunStatus.WON, "Cabinet must settle before victory check")
	var snapshot := sim.state.indicators.duplicate(true)
	_expect(sim.apply_command(Command.end_turn()).is_empty(), "Finished runs reject commands")
	_expect(snapshot == sim.state.indicators, "Finished state must be frozen")
	# Zero-confidence failure is reachable after clamping, including direct effects.
	sim = _new_run(&"arcadia")
	_setup(sim)
	sim.state.indicators[&"confidence"] = 11
	sim._fire_event(&"arcadia_ev_bank_run")
	sim.apply_command(Command.resolve_event(1))
	_expect(sim.state.run_status == GameState.RunStatus.LOST, "Event failure must be checked immediately")
	# State is clean across runs and all starting derived values are initialized.
	sim = _new_run(&"example_country")
	_expect(sim.state.cabinets.is_empty() and sim.state.aids.is_empty(), "Restart must clear inventory")
	_expect(sim.state.indicators.size() == 6 and sim.state.indicators.has(&"growth"), "Opening state must contain five economic indicators and derived growth only")
	var offered_laws: Array[StringName] = []
	for group in sim._build_year_end_rewards():
		for option: Reward in group["options"]:
			if option.type == Reward.Type.CARD and sim.card_db[option.id].once_per_run:
				_expect(not offered_laws.has(option.id), "Law cannot be offered in both card groups")
				offered_laws.append(option.id)
	# A goal achieved on the last month takes precedence over the deadline.
	_setup(sim)
	sim.state.year = 3
	sim.state.turn = 3 * int(sim.rules["turns_per_year"])
	sim.state.turn_in_year = int(sim.rules["turns_per_year"])
	sim.state.indicators[&"gdp"] = 150
	sim.state.indicators[&"unemployment"] = 3
	sim.state.indicators[&"inflation"] = 2
	sim.apply_command(Command.end_turn())
	_expect(sim.state.run_status == GameState.RunStatus.WON, "Final-month victory must beat deadline")
	sim = _new_run(&"example_country")
	_setup(sim)
	sim.state.year = 3
	sim.state.turn = 3 * int(sim.rules["turns_per_year"])
	sim.state.turn_in_year = int(sim.rules["turns_per_year"])
	sim.state.indicators[&"gdp"] = 90
	sim.apply_command(Command.end_turn())
	_expect(sim.state.run_status == GameState.RunStatus.LOST and sim.state.flags.get("loss_reason") == "deadline", "Deadline must end unfinished runs")
	var r1 := Rng.new(42)
	var r2 := Rng.new(42)
	for i in 100:
		_expect(r1.next_int(1000) == r2.next_int(1000), "RNG must be reproducible")


func _test_economy() -> void:
	var sim := _new_run(&"arcadia")
	_setup(sim)
	var initial_budget := sim.state.budget
	sim.economy.tick(sim.state, sim.rng)
	_expect(sim.state.budget == initial_budget, "Economic settlement must not automatically collect or spend budget")
	sim.state.modifiers.clear()
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {"scope": "coefficient", "target": "gdp_auto", "op": "add", "value": 100, "duration": -1}}), sim.state, sim.rng)
	var before := float(sim.state.indicators[&"gdp"])
	sim.economy.tick(sim.state, sim.rng)
	_expect(sim.state.indicators[&"gdp"] <= before * 1.080001, "Actual growth must respect its cap")
	# Scheduled crises override probability, with no random-event interference.
	sim.rules["random_event_chance"] = 0
	for turn_number in [24, 26, 28]:
		sim.state.turn = turn_number
		sim._schedule_event()
		_expect(sim.state.pending_event == sim.scenario_db[&"arcadia"].scheduled_events[turn_number], "Scheduled crisis missing")
	sim.rules["random_event_chance"] = 0.35


func _test_indicator_reset() -> void:
	var sim := _new_run(&"arcadia")
	var stale: StringName = &"stale_scenario_indicator"
	sim.economy.register_indicator(stale)
	var stale_equation := func(_state: GameState, _model: EconomyModel, _rng: Rng) -> float:
		return 1.0
	sim.economy.equations[stale] = stale_equation
	sim.state.indicators[stale] = 42.0
	_expect(sim.economy.indicator_ids.has(stale), "Stale indicator setup must be registered")
	sim.start_run(&"example_country")
	_expect(not sim.economy.indicator_ids.has(stale), "Restart must drop indicators from the previous scenario")
	_expect(not sim.state.indicators.has(stale), "Restart must clear stale indicator values")
	for id in sim.scenario_db[&"example_country"].indicators:
		_expect(sim.economy.indicator_ids.has(id), "Restart must keep every scenario indicator: %s" % id)
	_expect(sim.economy.derived_ids.has(&"growth"), "Restart must preserve derived definitions")
	_expect(sim.economy.equations.has(&"gdp"), "Restart must preserve equation definitions")
	sim.economy.tick(sim.state, sim.rng)
	sim.economy.refresh_derived(sim.state)
	_expect(not sim.state.indicators.has(stale), "Stale indicator must not return after tick or refresh")
	sim.economy.equations.erase(stale)
	sim.economy.indicator_ids.erase(stale)
	sim.state.indicators.erase(stale)


func _test_reward_pool_resolution() -> void:
	var configured := {"cards": [&"beta", &"alpha", &"beta", &"", &"alpha", &"gamma", ""]}
	var expected: Array[StringName] = [&"beta", &"alpha", &"gamma"]
	_expect(controller._resolve_pool(configured, "cards", controller.cards) == expected, "Configured pools must keep only the first occurrence of each non-empty ID")
	var fallback := {&"": true, &"alpha": true, &"beta": true}
	var fallback_expected: Array[StringName] = [&"alpha", &"beta"]
	_expect(controller._resolve_pool({&"cards": []}, "cards", fallback) == fallback_expected, "Empty configured pools must fall back without empty IDs")


func _test_ui() -> void:
	var ui := GameUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	_expect(not ui._sidebar.visible, "Log sidebar must start collapsed")
	ui._sidebar_button.button_pressed = true
	await process_frame
	await process_frame
	_expect(ui._log.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "All three UI columns must fit")
	_expect(ui._log.size.y > 150, "Event log must have usable vertical space alongside the forecast")
	_expect(ui._overlay_root.get_child(0).size.y <= root.get_visible_rect().size.y, "Scrollable modal must fit viewport")
	_expect(ui._overlay_root.visible, "Rewards UI must be visible")
	ui._dispatch(Command.choose_reward([]))
	if controller.simulation.state.pending_event != &"":
		ui._dispatch(Command.resolve_event(0))
	_expect(not ui._end_turn_button.disabled, "End turn must be available in main phase")
	_expect(ui._deck_label.text != "", "Deck counts must be visible")
	ui._dispatch(Command.end_turn())
	ui.free()


func _autoplay(scenario: StringName, seed_value: int, policy: String) -> Dictionary:
	var sim := _new_run(scenario, seed_value)
	var bot_rng := Rng.new(seed_value + 100000)
	var steps := 0
	while sim.state.run_status == GameState.RunStatus.RUNNING and steps < 1000:
		steps += 1
		var state := sim.state
		if not state.pending_rewards.is_empty():
			var picks: Array = []
			for group in state.pending_rewards:
				var pick := -1
				if policy != "passive":
					pick = bot_rng.next_int(group["options"].size())
					if policy == "planned":
						var best := -INF
						for i in group["options"].size():
							var reward: Reward = group["options"][i]
							var score := _reward_score(sim, reward)
							if score > best:
								best = score
								pick = i
				picks.append(pick)
			sim.apply_command(Command.choose_reward(picks))
		elif state.pending_event != &"":
			var definition: EconomyEventDef = sim.event_db[state.pending_event]
			var available: Array[int] = []
			for index in definition.choices.size():
				if sim.event_choice_available(index):
					available.append(index)
			_expect(not definition.has_choices() or not available.is_empty(), "Every event must have an affordable choice")
			var choice: int = available[0] if not available.is_empty() else -1
			if policy == "random":
				if not available.is_empty():
					choice = available[bot_rng.next_int(available.size())]
			elif policy == "planned":
				var best := -INF
				for i in available:
					var score := _effects_score(sim, definition.choices[i].effects)
					if score > best:
						best = score
						choice = i
			sim.apply_command(Command.resolve_event(choice))
		else:
			if policy != "passive":
				for entry in state.aids.duplicate():
					var aid: AidDef = entry["def"]
					if policy == "random" or (aid.id == &"arcadia_aid_fireside" and sim.economy.value(state, &"confidence") < 45) or (aid.id != &"arcadia_aid_fireside" and state.budget < 6):
						sim.apply_command(Command.use_aid(aid.id))
				var best_card: StringName = &""
				var best_score := 0.0
				for id in state.hand:
					var card: CardDef = sim.card_db[id]
					var costs := sim.card_costs(id)
					if not sim.can_spend_budget(int(costs["budget"])) or (int(costs["political"]) > 0 and state.political_capital < int(costs["political"])):
						continue
					var score := bot_rng.next_float() + 0.01 if policy == "random" else _effects_score(sim, card.effects) / (1 + card.cost * 0.2 + card.political_cost * 0.1)
					if score > best_score:
						best_score = score
						best_card = id
				if best_card != &"":
					sim.apply_command(Command.play_card(best_card))
			# One card per month is deliberately a simple baseline, not an optimal solver.
			sim.apply_command(Command.end_turn())
		for value in state.indicators.values():
			_expect(is_finite(float(value)), "Non-finite economy value")
		_expect(state.budget >= 0 or StatusRules.allows_deficit(state, sim.status_db), "Negative budget requires deficit reform")
		for removed in REMOVED_FIELDS:
			_expect(not state.indicators.has(StringName(removed)), "Removed field must not reappear during play: %s" % removed)
	_expect(steps < 1000, "Run stalled: %s seed %d" % [scenario, seed_value])
	return {"won": sim.state.run_status == GameState.RunStatus.WON, "turn": sim.state.turn}


func _reward_score(sim: Simulation, reward: Reward) -> float:
	if reward.type == Reward.Type.CARD:
		var card: CardDef = sim.card_db[reward.id]
		return _effects_score(sim, card.effects) / (1 + card.cost * 0.2)
	if reward.type == Reward.Type.CABINET:
		var priorities := {&"arcadia_cab_braintrust": 6, &"arcadia_cab_interior": 5, &"arcadia_cab_labor": 4, &"arcadia_cab_fed": 3, &"arcadia_cab_treasury": 2, &"arcadia_cab_agriculture": 1}
		return float(priorities.get(reward.id, 1))
	return 3.0 if reward.id == &"arcadia_aid_foreign_loan" else 2.0


func _effects_score(sim: Simulation, effects: Array) -> float:
	var score := 0.0
	# Sustained investment now feeds prices through monthly growth. Avoid
	# endlessly stimulating an overheated economy instead of stabilizing it.
	var growth_weight := 0.25 if sim.economy.value(sim.state, &"inflation") >= 5 else 2.5
	for effect: Effect in effects:
		if effect.condition != null and not effect.condition.evaluate(sim.state, sim.economy):
			continue
		var p := effect.params
		if effect.kind == Effect.Kind.BRANCH:
			var condition := Condition.from_dict(p.get("condition", {}))
			var nested: Array[Effect] = []
			for raw in p.get("then" if condition.evaluate(sim.state, sim.economy) else "else", []):
				nested.append(Effect.from_dict(raw))
			score += _effects_score(sim, nested)
		elif effect.kind == Effect.Kind.GAIN_BUDGET:
			score += float(p.get("amount", 0)) * (0.5 if sim.state.budget < 8 else 0.1)
		elif effect.kind == Effect.Kind.GAIN_POLITICAL_CAPITAL:
			score += float(p.get("amount", 0)) * (0.6 if sim.state.political_capital < 4 else 0.15)
		elif effect.kind == Effect.Kind.GRANT_STATUS:
			# This conservative one-card/month bot cannot exploit full combo value.
			var ability_scores := {"executive_mandate": 2.5, "earmarked_funds": 2.5, "policy_synergy": 0.5}
			score += float(ability_scores.get(String(p.get("status", "")), 0))
		elif effect.kind == Effect.Kind.ADJUST_INDICATOR or effect.kind == Effect.Kind.APPLY_MODIFIER:
			var amount := float(p.get("amount", p.get("value", 0)))
			var target := StringName(p.get("target", ""))
			if p.get("scope", "") == "coefficient":
				if p.get("op", "add") == "override":
					amount -= sim.economy.coefficient(sim.state, target)
				var duration := int(p.get("duration", -1))
				var horizon := mini(duration, 12) if duration > 0 else 12
				match target:
					&"gdp_auto": score += amount * horizon * growth_weight
					&"natural_unemployment": score -= amount * 2
					&"u_revert": score += amount * 100
				continue
			var current := sim.economy.value(sim.state, target)
			match target:
				&"gdp": score += amount * growth_weight
				&"unemployment": score -= amount * (2 if current > 6 else 0.3)
				&"confidence": score += amount * (0.5 if current < 45 else 0.15)
				&"inflation": score += (absf(current - 2) - absf(current + amount - 2)) * 0.6
				&"interest_rate": score -= amount * 0.4
				&"bank_protection", &"market_protection": score += 7 if sim.state.turn < 24 else 0.5
	return score
