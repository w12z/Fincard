extends SceneTree

const CARD := &"reform_permanent_coordination"
var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _test_scenario(scenario: StringName) -> void:
	var sim := controller.simulation
	sim.card_reward_pool.assign([CARD])
	controller.start_run(scenario)
	var card: CardDef = controller.cards[CARD]
	_expect(card.rarity == &"rare" and card.card_type == &"reform" and card.once_per_run, "The new political income card is a rare once-only reform")
	_expect(card.reward_min_turn == 1 and sim._reward_available(Reward.Type.CARD, CARD), "Both countries can obtain it from their opening reward")
	var definition: ScenarioDef = controller.scenarios[scenario]
	_expect(not definition.starting_deck.has(CARD), "Opening availability must not change the starter deck")
	var offered := 0
	var picks: Array = []
	for group in sim.state.pending_rewards:
		var pick := -1
		for index in group["options"].size():
			var reward: Reward = group["options"][index]
			if reward.type == Reward.Type.CARD and reward.id == CARD:
				offered += 1
				pick = index
		picks.append(pick)
	_expect(offered == 1, "Opening meetings offer the same once-only reform in at most one group")
	sim.apply_command(Command.choose_reward(picks))
	_expect(not sim._reward_available(Reward.Type.CARD, CARD), "An owned reform is excluded from later rewards")
	sim.state.hand.assign([CARD])
	sim.state.budget = 10
	sim.state.political_capital = 3
	sim.apply_command(Command.play_card(CARD))
	_expect(sim.state.budget == 6 and sim.state.political_capital == 0, "The reform pays four budget and three political points without an immediate refund")
	_expect(sim.political_capital_per_turn() == 4, "The persistent modifier raises the turn reset from three to four")
	_expect(sim.state.flags.get("enacted:" + String(CARD), false), "The reform is marked as enacted")
	_expect(not sim.state.hand.has(CARD) and not sim.state.deck.has(CARD) and not sim.state.discard.has(CARD), "An enacted reform is removed instead of cycling into discard")
	var found := false
	for modifier in sim.state.modifiers:
		if modifier.target == &"political_capital_gain":
			found = modifier.scope == Modifier.SCOPE_INDICATOR and modifier.remaining_turns == -1 and modifier.value == 1
	_expect(found, "Political reset income uses the existing permanent unified modifier system")
	var preview := sim.forecast_next_turn()
	_expect(preview.political_capital == 4 and sim.state.political_capital == 0, "Forecast shows next-turn political income without paying it early")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.turn == 2 and sim.state.political_capital == 4, "The next turn grants four political points")
	sim.state.political_capital = 0
	sim.apply_command(Command.end_turn())
	_expect(sim.state.turn == 3 and sim.state.political_capital == 4, "The extra point applies every turn, not just once")
	_expect(not sim._reward_available(Reward.Type.CARD, CARD), "An enacted reform cannot be obtained again")
	controller.start_run(scenario)
	_expect(sim.political_capital_per_turn() == 3, "A new game clears the previous reform bonus")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_test_scenario(&"example_country")
	_test_scenario(&"arcadia")
	controller.free()
	await process_frame
	print("POLITICAL INCOME REFORM TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
