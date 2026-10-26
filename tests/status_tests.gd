extends SceneTree

var controller: GameController
var failures: int = 0
var capture_directory: String = ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_directory = arg.trim_prefix("--capture=")
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare() -> Simulation:
	var sim := controller.simulation
	sim.rng = Rng.new(7)
	sim.start_run(&"example_country")
	sim.apply_command(Command.choose_reward([]))
	sim.state.budget = 50
	sim.state.political_capital = 20
	return sim


func _grant(sim: Simulation, id: StringName) -> void:
	sim.resolver.resolve(Effect.from_dict({"kind": "grant_status", "params": {"status": id}}), sim.state, sim.rng)


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_mandate()
	_test_discount()
	_test_synergy()
	await _test_ui()
	controller.free()
	await process_frame
	print("STATUS TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_mandate() -> void:
	var sim := _prepare()
	sim.state.hand.assign([&"reform_executive_mandate", &"starter_infrastructure"])
	sim.apply_command(Command.play_card(&"reform_executive_mandate"))
	_expect(sim.state.statuses.has(&"executive_mandate"), "Reform must grant its permanent ability")
	_expect(sim.state.budget == 46 and sim.state.political_capital == 17, "The reform itself must pay its full cost")
	_expect(sim.card_costs(&"starter_infrastructure")["political"] == 2, "Unlocking ability must not reset first-card tracking")
	_expect(not sim._reward_available(Reward.Type.CARD, &"reform_executive_mandate"), "Ability law must stay exhausted")
	sim.apply_command(Command.end_turn())
	sim.state.hand.assign([&"starter_infrastructure", &"starter_infrastructure"])
	sim.state.political_capital = 0
	sim._gain_aid(&"example_aid")
	sim.apply_command(Command.use_aid(&"example_aid"))
	_expect(sim.state.cards_played_this_turn == 0, "Using external aid must not count as playing a card")
	var original_budget := sim.state.budget
	sim.state.budget = 0
	_expect(sim.apply_command(Command.play_card(&"starter_infrastructure")).is_empty(), "Political waiver must not waive budget")
	_expect(sim.state.cards_played_this_turn == 0, "Failed play must not consume the opportunity")
	sim.state.budget = original_budget
	var costs := sim.card_costs(&"starter_infrastructure")
	_expect(costs["political"] == 0 and costs["budget"] == 4, "First card must waive political cost only")
	sim.card_costs(&"starter_infrastructure")
	_expect(sim.state.cards_played_this_turn == 0, "Previewing costs must not consume ability")
	var events := sim.apply_command(Command.play_card(&"starter_infrastructure"))
	_expect(not events.is_empty() and sim.state.political_capital == 0, "First card must be playable at zero political capital")
	_expect(sim.state.budget == original_budget - 4, "Waived card must still pay full budget")
	_expect(sim.card_costs(&"starter_infrastructure")["political"] == 2, "Second card must have normal political cost")
	_expect(sim.apply_command(Command.play_card(&"starter_infrastructure")).is_empty(), "Second card cannot bypass insufficient points")
	_grant(sim, &"executive_mandate")
	_expect(sim.state.statuses.size() == 1, "Duplicate status grants must not stack or reset uses")
	# A card whose printed cost is zero still counts as the first card.
	sim.apply_command(Command.end_turn())
	var zero := CardDef.from_dict({"id": "test_zero", "card_type": "policy", "cost": 0, "political_cost": 0})
	sim.card_db[zero.id] = zero
	sim.state.hand.assign([zero.id, &"starter_infrastructure"])
	sim.apply_command(Command.play_card(zero.id))
	_expect(sim.card_costs(&"starter_infrastructure")["political"] == 2, "A zero-cost first card also consumes the waiver")
	sim.card_db.erase(zero.id)
	# Carry through an annual transition; start-of-turn resets but status persists.
	sim.state.turn_in_year = int(sim.rules["turns_per_year"])
	sim.apply_command(Command.end_turn())
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.state.cards_played_this_turn == 0 and sim.state.statuses.has(&"executive_mandate"), "Ability must persist across years and refresh each month")
	_prepare()
	_expect(sim.state.statuses.is_empty(), "Starting a new run must clear all abilities")


func _test_discount() -> void:
	var sim := _prepare()
	_grant(sim, &"executive_mandate")
	_grant(sim, &"earmarked_funds")
	sim.state.hand.assign([&"example_card", &"starter_infrastructure", &"starter_small_business"])
	sim.apply_command(Command.play_card(&"example_card"))
	_expect(sim.card_costs(&"starter_infrastructure")["budget"] == 2, "Non-investment cards must not consume the investment discount")
	sim.apply_command(Command.play_card(&"starter_infrastructure"))
	_expect(sim.card_costs(&"starter_small_business")["budget"] == 2, "Only the first investment gets a discount")
	sim.apply_command(Command.end_turn())
	var costs := sim.card_costs(&"starter_small_business")
	_expect(costs["budget"] == 0 and costs["political"] == 0, "Independent abilities must combine and never create negative costs")
	sim.state.budget = 0
	sim.state.political_capital = 0
	sim.state.hand.assign([&"starter_small_business"])
	sim.apply_command(Command.play_card(&"starter_small_business"))
	_expect(sim.state.hand.is_empty() and sim.state.budget == 0 and sim.state.political_capital == 0, "Combined free play must not create resources")
	sim.apply_command(Command.end_turn())
	sim.state.political_capital = -2
	sim.state.hand.assign([&"starter_small_business"])
	sim.apply_command(Command.play_card(&"starter_small_business"))
	_expect(sim.state.hand.is_empty() and sim.state.political_capital == -2, "A waived political cost must not require or create points even during political overdraft")


func _test_synergy() -> void:
	var sim := _prepare()
	_grant(sim, &"policy_synergy")
	sim.state.hand.assign([&"starter_small_business", &"starter_small_business", &"starter_small_business", &"starter_small_business"])
	sim.state.deck.assign([&"starter_training", &"example_card"])
	for i in 2:
		sim.apply_command(Command.play_card(&"starter_small_business"))
	_expect(sim.state.hand.size() == 2, "Synergy must not draw before the third card")
	var events := sim.apply_command(Command.play_card(&"starter_small_business"))
	_expect(sim.state.hand.size() == 3 and sim.state.deck.is_empty(), "Third card must draw two additional cards")
	var triggers := 0
	for event: Event in events:
		if event.kind == Event.Kind.STATUS_TRIGGERED:
			triggers += 1
	_expect(triggers == 1, "Synergy must trigger exactly once")
	sim.apply_command(Command.play_card(&"starter_small_business"))
	_expect(sim.state.hand.size() == 2, "Fourth card must not trigger extra draws")
	sim.apply_command(Command.end_turn())
	sim.state.hand.assign([&"starter_small_business", &"starter_small_business", &"starter_small_business"])
	sim.state.deck.assign([&"starter_training", &"example_card"])
	for i in 3:
		sim.apply_command(Command.play_card(&"starter_small_business"))
	_expect(sim.state.hand.size() == 2, "Synergy must refresh and trigger again next turn")
	sim = _prepare()
	sim.state.hand.assign([&"starter_training", &"starter_training", &"reform_policy_synergy"])
	sim.apply_command(Command.play_card(&"starter_training"))
	sim.apply_command(Command.play_card(&"starter_training"))
	sim.apply_command(Command.play_card(&"reform_policy_synergy"))
	_expect(sim.state.hand.is_empty(), "Ability-granting card must not retroactively trigger its own third-card effect")
	_expect(StatusRules.progress(controller.statuses[&"policy_synergy"], sim.state) == "下回合可触发", "Badge must not claim a trigger that never occurred")


func _test_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	_grant(sim, &"executive_mandate")
	_grant(sim, &"earmarked_funds")
	_grant(sim, &"policy_synergy")
	sim.state.political_capital = 0
	sim.state.hand.assign([&"starter_small_business", &"starter_infrastructure"])
	ui._render()
	for i in 4:
		await process_frame
	var icons := ui._effect_icons
	_expect(icons.get_child_count() == ModifierDisplay.entries(sim, controller.labels).size(), "Base parameters, innate modifiers and all abilities share one badge bar")
	_expect(is_equal_approx(icons.get_child(0).position.y, icons.get_child(3).position.y), "Modifier icons should fit in a compact row")
	_expect(ui._log.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "Ability badges must not push the game UI outside the viewport")
	_expect("行政授权" in icons.get_child(1).tooltip_text, "Badges must explain the ability on hover")
	var card: Button = ui._hand_box.get_child(0)
	_expect(not card.disabled and card.find_child("PoliticalAmount", true, false).get_node("Amount").text == "0（原1）", "UI must allow the discounted card and show actual costs")
	if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(capture_directory.path_join("fincard-status-abilities.png")) == OK, "Ability screenshot must save")
	ui._dispatch(Command.play_card(&"starter_small_business"))
	icons = ui._effect_icons
	_expect("0/1" in icons.get_child(1).text and "0/1" in icons.get_child(2).text, "Badges must update after consuming an opportunity")
	_expect(ui._hand_box.get_child(0).disabled, "UI must restore normal costs after the first play")
	ui.free()
