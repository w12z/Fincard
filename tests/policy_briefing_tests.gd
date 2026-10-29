extends SceneTree

var failures := 0
var controller: GameController
const CARD := &"reform_policy_briefing"


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare(scenario: StringName) -> Simulation:
	controller.start_run(scenario)
	var sim := controller.simulation
	sim.apply_command(Command.choose_reward([]))
	sim.state.budget = 20
	sim.state.political_capital = 10
	sim.state.hand.assign([CARD])
	sim.state.deck.clear()
	sim.state.discard.clear()
	for i in 20:
		sim.state.deck.append(&"starter_training")
	return sim


func _test_card(scenario: StringName) -> void:
	var sim := _prepare(scenario)
	var card: CardDef = controller.cards[CARD]
	_expect(card.rarity == &"rare" and card.card_type == &"reform" and card.once_per_run, "Briefing is a rare one-time reform")
	sim.state.hand.clear()
	_expect(sim._reward_available(Reward.Type.CARD, CARD), "Briefing is available in both countries' opening reward pools")
	sim._enter_main()
	_expect(sim.state.hand.size() == 5, "Unmodified starting draw remains five")
	sim.state.hand.assign([CARD])
	sim.apply_command(Command.play_card(CARD))
	_expect(sim.state.budget == 17 and sim.state.political_capital == 8, "Briefing costs three budget and two political points")
	_expect(sim.state.hand.is_empty(), "Enactment does not immediately draw a card")
	_expect(sim.economy.value(sim.state, &"turn_draw_bonus") == 1, "Draw bonus is stored in the unified modifier list")
	_expect(sim.state.flags.get("enacted:" + String(CARD), false) and not sim.state.discard.has(CARD), "Reform is enacted once and removed instead of discarded")
	_expect(not sim._reward_available(Reward.Type.CARD, CARD), "Enacted reform cannot be rewarded again")
	var text := TextFormatter.effects_text(controller.labels, card.effects)
	_expect(text.contains("永久") and text.contains("每回合起始抽牌加成 +1"), "Card effect has a readable permanent draw description")
	var found := false
	for entry in ModifierDisplay.entries(sim, controller.labels):
		if entry["key"] == "indicator:turn_draw_bonus":
			found = entry["counter"] == "+1" and entry["name"] == "每回合起始抽牌加成"
	_expect(found, "Permanent draw bonus is visible in the modifier bar")
	var deck := sim.state.deck.duplicate()
	var forecast := sim.forecast_next_turn()
	_expect(forecast.hand.size() == 6 and sim.state.hand.is_empty() and sim.state.deck == deck, "Forecast includes six-card draw without mutating real piles")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.hand == forecast.hand and sim.state.hand.size() == 6, "Next turn draws six cards and matches forecast")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.hand.size() == 6 and sim.economy.value(sim.state, &"turn_draw_bonus") == 1, "Draw bonus remains active on subsequent turns")


func _test_other_draws() -> void:
	var sim := _prepare(&"example_country")
	sim.apply_command(Command.play_card(CARD))
	sim._draw(2)
	_expect(sim.state.hand.size() == 2, "Bonus does not affect draws outside turn-start drawing")
	controller.start_run(&"example_country")
	sim = controller.simulation
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.hand.size() == 5 and sim.economy.value(sim.state, &"turn_draw_bonus") == 0, "New run clears the acquired draw bonus")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	for scenario in [&"example_country", &"arcadia"]:
		_test_card(scenario)
	_test_other_draws()
	controller.free()
	await process_frame
	print("POLICY BRIEFING TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
