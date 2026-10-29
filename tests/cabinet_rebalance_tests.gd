extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare(scenario: StringName = &"example_country") -> Simulation:
	controller.start_run(scenario)
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.budget = 100
	sim.state.political_capital = 20
	sim.state.hand.clear()
	sim.state.deck.clear()
	sim.state.discard.clear()
	for i in 30:
		sim.state.deck.append(&"starter_training")
	return sim


func _play(sim: Simulation, id: StringName) -> Array[Event]:
	sim.state.hand.append(id)
	var events := sim.apply_command(Command.play_card(id))
	_expect(not events.is_empty(), "Card plays successfully: %s" % id)
	return events


func _automatic_ids(events: Array[Event]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for event in events:
		if event.kind == Event.Kind.CARD_PLAYED and event.params.get("automatic", false):
			ids.append(StringName(event.params["card_id"]))
	return ids


func _grant(sim: Simulation, id: StringName) -> Modifier:
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
		"scope": "special", "target": id, "duration": -1,
	}}), sim.state, sim.rng)
	var modifier := StatusRules.find_modifier(sim.state, id)
	modifier.ready_turn = sim.state.turn
	return modifier


func _test_existing_cabinets() -> void:
	var sim := _prepare()
	var growth := sim.economy.coefficient(sim.state, &"gdp_auto")
	var confidence := sim.economy.value(sim.state, &"confidence")
	sim._appoint_cabinet(&"arcadia_cab_braintrust")
	_expect(sim.rarity_weight(&"rare") == 5 and sim.rarity_weight(&"common") == 5 and sim.rarity_weight(&"legendary") == 1, "Celine adds exactly three rare weight")
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), growth + 0.1) and sim.economy.value(sim.state, &"confidence") == confidence + 2, "Celine retains her growth and appointment confidence effects")
	sim = _prepare()
	var baseline := sim.forecast_next_turn()
	sim._appoint_cabinet(&"arcadia_cab_labor")
	var forecast := sim.forecast_next_turn()
	_expect(is_equal_approx(float(forecast.indicators[&"unemployment"]), float(baseline.indicators[&"unemployment"])), "Vera no longer changes unemployment")
	_expect(is_equal_approx(float(forecast.indicators[&"confidence"]), float(baseline.indicators[&"confidence"]) + 1), "Vera grants one confidence after settlement")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.indicators == forecast.indicators, "Vera's actual settlement matches forecast")
	sim = _prepare()
	growth = sim.economy.coefficient(sim.state, &"gdp_auto")
	var income := sim.annual_income()
	var interest := sim.economy.value(sim.state, &"interest_rate")
	sim._appoint_cabinet(&"example_cabinet")
	sim._appoint_cabinet(&"arcadia_cab_fed")
	_expect(sim.state.budget == 100 and sim.state.political_capital == 20, "Irene and Marlo do not grant turn-start resources immediately on appointment")
	_expect(sim.annual_income() == income and sim.economy.coefficient(sim.state, &"gdp_auto") == growth, "Irene no longer modifies annual income or growth")
	_expect(sim.economy.value(sim.state, &"interest_rate") == interest, "Marlo no longer modifies interest")
	for turn in 2:
		forecast = sim.forecast_next_turn()
		var budget := sim.state.budget
		sim.apply_command(Command.end_turn())
		_expect(sim.state.budget == budget + 1 and sim.state.political_capital == sim.political_capital_per_turn() + 1, "Irene and Marlo grant one resource on each turn start")
		_expect(sim.state.budget == forecast.budget and sim.state.political_capital == forecast.political_capital, "Per-turn resource grants match forecast")
	sim.state.turn = 8
	sim.state.turn_in_year = 8
	sim.state.budget = 10
	sim.apply_command(Command.end_turn())
	while not sim.state.pending_rewards.is_empty():
		sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.turn == 9 and sim.state.budget == 5 + income + 1 and sim.state.political_capital == sim.political_capital_per_turn() + 1, "Year starts grant one budget and one political point, without the old annual bonuses")
	var budget := sim.state.budget
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.budget == budget, "Repeated reward commands cannot duplicate turn-start income")


func _test_first_card_discount() -> void:
	var sim := _prepare()
	sim._appoint_cabinet(&"cabinet_finn")
	var costs := sim.card_costs(&"starter_infrastructure")
	_expect(costs["budget"] == 3 and costs["political"] == 1, "Finn discounts both costs of the first card")
	_play(sim, &"starter_infrastructure")
	_expect(sim.state.budget == 97 and sim.state.political_capital == 19, "The first card actually pays discounted costs")
	costs = sim.card_costs(&"starter_infrastructure")
	_expect(costs["budget"] == 4 and costs["political"] == 2, "Second card receives no first-card discount")
	sim.apply_command(Command.end_turn())
	_expect(sim.card_costs(&"starter_infrastructure")["budget"] == 3, "Finn's discount resets each turn")
	sim = _prepare()
	sim._appoint_cabinet(&"cabinet_finn")
	costs = sim.card_costs(&"arcadia_reform_tax_wealth")
	_expect(costs["budget"] == 0 and costs["political"] == 2, "Zero budget cost is clamped, not refunded")
	costs = sim.card_costs(&"policy_procedural_motion")
	_expect(costs["budget"] == 1 and costs["political"] == 0, "Zero political cost is clamped, not refunded")
	_grant(sim, &"executive_mandate")
	costs = sim.card_costs(&"starter_infrastructure")
	_expect(costs["budget"] == 3 and costs["political"] == 0, "Finn stacks safely with first-card political waiver")
	sim._resolve_played_card(&"starter_small_business", true)
	_expect(sim.card_costs(&"starter_infrastructure")["budget"] == 4, "An automatic first play occupies the first-card slot")


func _test_last_card_replay() -> void:
	var sim := _prepare()
	sim._appoint_cabinet(&"cabinet_rowan")
	var events := sim.apply_command(Command.end_turn())
	_expect(_automatic_ids(events).is_empty(), "No plays means no last-card replay")
	_play(sim, &"starter_small_business")
	_play(sim, &"policy_procedural_motion")
	var history := sim.state.played_cards_this_turn.duplicate()
	var modifier := StatusRules.find_modifier(sim.state, &"last_card_replay")
	var budget := sim.state.budget
	var copies := sim.state.deck.size() + sim.state.hand.size() + sim.state.discard.size()
	var forecast := sim.forecast_next_turn()
	_expect(sim.state.played_cards_this_turn == history and not modifier.data.has("queued_card"), "Forecast does not consume or populate the real replay queue")
	_expect(forecast.cards_played_this_turn == 1 and forecast.played_cards_this_turn == [&"policy_procedural_motion"], "Forecast replays the last card, not the first")
	events = sim.apply_command(Command.end_turn())
	_expect(_automatic_ids(events) == [&"policy_procedural_motion"], "Next turn emits exactly one automatic last-card play")
	_expect(sim.state.budget == budget and sim.state.political_capital == sim.political_capital_per_turn() + 1, "Last-card play is free and still resolves the policy's political gain")
	_expect(sim.state.cards_played_this_turn == 1 and sim.state.flags["policies_played_this_turn"] == 1 and sim.state.flags["political_policies_played_this_turn"] == 1, "Automatic last-card play advances all applicable counters")
	_expect(sim.state.deck.size() + sim.state.hand.size() + sim.state.discard.size() == copies and not modifier.data.has("queued_card"), "Replay consumes its queue once and adds no card copies")
	_expect(sim.state.budget == forecast.budget and sim.state.political_capital == forecast.political_capital and sim.state.hand == forecast.hand, "Real next turn matches forecast resources and piles")
	events = sim.apply_command(Command.end_turn())
	_expect(_automatic_ids(events) == [&"policy_procedural_motion"], "An automatic-only turn still has a last played card, replayed once next turn")


func _test_replay_triggers_and_rewards() -> void:
	var sim := _prepare()
	_grant(sim, &"project_continuity")
	sim._appoint_cabinet(&"cabinet_rowan")
	var research := _grant(sim, &"investment_research")
	_grant(sim, &"rotation_execution")
	_play(sim, &"starter_small_business")
	_play(sim, &"arcadia_policy_bond_yield")
	research.data["progress"] = 2
	var budget := sim.state.budget
	var events := sim.apply_command(Command.end_turn())
	_expect(_automatic_ids(events) == [&"starter_small_business", &"arcadia_policy_bond_yield"], "First-card reform and last-card adviser replay their independent cards")
	_expect(sim.state.cards_played_this_turn == 2 and sim.state.investments_played_this_turn == 1 and sim.state.flags["policies_played_this_turn"] == 1, "Both queued cards participate in play counters")
	_expect(research.data["progress"] == 0 and sim.state.hand.size() == 6 and sim.state.political_capital == sim.political_capital_per_turn() + 1, "Queued cards trigger research draw and type-synergy refund")
	_expect(sim.state.budget == budget, "Both queued cards are free")
	sim = _prepare()
	sim._appoint_cabinet(&"cabinet_rowan")
	sim.state.turn = 4
	sim.state.turn_in_year = 4
	_play(sim, &"starter_small_business")
	events = sim.apply_command(Command.end_turn())
	var modifier := StatusRules.find_modifier(sim.state, &"last_card_replay")
	_expect(sim.state.turn == 4 and not sim.state.pending_rewards.is_empty() and modifier.data.get("queued_card") == &"starter_small_business", "Reward interruption preserves the queue without early automatic play")
	_expect(_automatic_ids(events).is_empty(), "Replay waits until reward selection finishes")
	events = sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.turn == 5 and _automatic_ids(events) == [&"starter_small_business"], "Queue resumes once at the next turn after rewards")
	sim = _prepare()
	sim._appoint_cabinet(&"cabinet_rowan")
	sim.state.turn = 8
	sim.state.turn_in_year = 8
	_play(sim, &"starter_efficiency")
	var growth := sim.economy.coefficient(sim.state, &"gdp_auto")
	events = sim.apply_command(Command.end_turn())
	_expect(_automatic_ids(events).is_empty(), "Last-card replay waits through year-end preparation")
	var automatic: Array[StringName] = []
	while not sim.state.pending_rewards.is_empty():
		automatic.append_array(_automatic_ids(sim.apply_command(Command.choose_reward([]))))
	_expect(sim.state.turn == 9 and automatic == [&"starter_efficiency"], "Even a one-time reform can be automatically played once across the year boundary")
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), growth + 0.12), "Automatic reform resolves its effect without paying again")
	_expect(not sim.state.hand.has(&"starter_efficiency") and not sim.state.deck.has(&"starter_efficiency") and not sim.state.discard.has(&"starter_efficiency"), "Automatic reform does not recreate its removed card")


func _test_availability_and_reset() -> void:
	for scenario in [&"example_country", &"arcadia"]:
		var sim := _prepare(scenario)
		for id in [&"cabinet_finn", &"cabinet_rowan"]:
			_expect(sim._reward_available(Reward.Type.CABINET, id), "Both countries can reward each new adviser")
			sim._appoint_cabinet(id)
			sim._appoint_cabinet(id)
			_expect(not sim._reward_available(Reward.Type.CABINET, id), "Appointed advisers cannot be offered twice")
		_expect(sim.state.cabinets.size() == 2, "Duplicate appointment cannot add advisers or effects")
	var sim := _prepare()
	_expect(StatusRules.find_modifier(sim.state, &"first_card_discount") == null and StatusRules.find_modifier(sim.state, &"last_card_replay") == null, "A fresh run clears both new abilities")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_existing_cabinets()
	_test_first_card_discount()
	_test_last_card_replay()
	_test_replay_triggers_and_rewards()
	_test_availability_and_reset()
	controller.free()
	await process_frame
	print("CABINET REBALANCE TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
