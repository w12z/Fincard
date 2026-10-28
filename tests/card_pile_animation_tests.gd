extends SceneTree

var failures := 0
var ui: GameUI
var controller: GameController
var capture_directory := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_directory = arg.trim_prefix("--capture=")
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _wait() -> void:
	var end := Time.get_ticks_msec() + 10000
	while (ui._pile_motion_active or ui._settlement_active or ui._flight_active) and Time.get_ticks_msec() < end:
		await process_frame
	_expect(not ui._pile_motion_active and not ui._settlement_active and not ui._flight_active, "Every pile/settlement/card animation completes")
	for frame in 6:
		await process_frame


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory.path_join(filename))


func _prepare() -> Simulation:
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	return controller.simulation


func _test_start_and_draw() -> void:
	var sim := _prepare()
	_expect(ui._pile_motion_active, "Opening five-card draw is animated")
	var hand_before := sim.state.hand.duplicate()
	ui._dispatch(Command.end_turn())
	_expect(sim.state.turn == 1 and sim.state.hand == hand_before, "Actions are blocked until opening draw lands")
	await _wait()
	_expect(ui._discard_pile.global_position.x < ui._hand_scroll.global_position.x, "Discard pile is left of the hand")
	_expect(ui._draw_pile.global_position.x >= ui._hand_scroll.get_global_rect().end.x, "Draw pile is right of the hand")
	sim.state.hand.assign([&"investment_inventory_restock", &"starter_training"])
	sim.state.deck.assign([&"starter_small_business", &"starter_infrastructure"])
	sim.state.budget = 30
	sim.state.political_capital = 10
	ui._render()
	for frame in 6:
		await process_frame
	ui._hand_box.get_child(0).pressed.emit()
	_expect(ui._flight_active and ui._pile_motion_active, "Draw effect waits for its played-card flight")
	while ui._flight_active:
		await process_frame
	await create_timer(0.13).timeout
	await _capture("fincard-draw-flight.png")
	await _wait()
	_expect(sim.state.cards_played_this_turn == 1 and sim.state.hand.size() == 2, "Drawing animation never changes the resolved card count")
	_expect(sim.state.hand.back() == &"starter_infrastructure", "The actually drawn card lands, not an invented card")
	for child in ui._hand_box.get_children():
		_expect(is_equal_approx(child.modulate.a, 1.0), "No drawn card stays hidden")
	_expect(ui._pile_motion.get_child_count() == 0, "Temporary drawing cards are freed")
	await _capture("fincard-card-piles.png")


func _test_discard_and_redraw_same_card() -> void:
	var sim := _prepare()
	await _wait()
	sim.state.hand.assign([&"starter_training", &"starter_small_business"])
	sim.state.deck.assign([&"starter_training", &"starter_infrastructure"])
	sim.state.flags["pending_discard_draw"] = [{"draw_count": 2}]
	ui._render()
	for frame in 6:
		await process_frame
	var total := sim.state.hand.size() + sim.state.deck.size() + sim.state.discard.size()
	ui._dispatch(Command.choose_discard_card(0))
	_expect(ui._pile_motion_active and not ui._overlay_root.visible, "Manual discard and replacement draws are staged without an overlay")
	await _wait()
	_expect(sim.state.discard.has(&"starter_training") and sim.state.hand.has(&"starter_training"), "Discarding and drawing the same ID is not lost by multiset comparison")
	_expect(total == sim.state.hand.size() + sim.state.deck.size() + sim.state.discard.size(), "Discard/draw transfers preserve real pile totals")


func _test_end_turn_reward() -> void:
	var sim := _prepare()
	await _wait()
	sim.state.turn = 4
	sim.state.turn_in_year = 4
	sim.state.hand.assign([&"starter_training", &"starter_small_business", &"starter_infrastructure"])
	ui._render()
	for frame in 6:
		await process_frame
	ui._dispatch(Command.end_turn())
	var saw_discard := false
	var end := Time.get_ticks_msec() + 7000
	while ui._settlement_active and Time.get_ticks_msec() < end:
		_expect(not ui._overlay_root.visible, "Reward remains hidden until settlement and discard finish")
		for child in ui._pile_motion.get_children():
			if str(child.get_meta("direction", "")) == "discard":
				if not saw_discard:
					await _capture("fincard-discard-flight.png")
				saw_discard = true
		await process_frame
	await _wait()
	_expect(saw_discard, "End-turn unplayed hand cards fly left instead of simply disappearing")
	_expect(ui._hand_box.get_child_count() == 0 and ui._played_table._cards.is_empty(), "Completed cards are cleared before reward")
	_expect(ui._overlay_root.visible, "Periodic reward appears after discarding")
	# Real runs can immediately draw into a random start-of-turn event. The
	# animation temporarily hides its already-built overlay; it must be restored.
	controller.rules["random_event_chance"] = 1.0
	ui._dispatch(Command.choose_reward([]))
	_expect(ui._pile_motion_active, "New-turn draw after reward is animated")
	await _wait()
	_expect(sim.state.turn == 5 and sim.state.hand.size() == 5, "Next turn receives exactly its five resolved cards")
	_expect(sim.state.pending_event != &"", "Regression fixture must draw into an event after periodic reward")
	_expect(ui._overlay_root.visible, "Event choices must reappear when post-reward draw animation finishes")
	if ui._overlay_root.visible:
		var event: EconomyEventDef = controller.events[sim.state.pending_event]
		ui._dispatch(Command.resolve_event(0 if event.has_choices() else -1))
		await _wait()
		_expect(sim.state.pending_event == &"" and sim._can_act(), "Restored event remains actionable rather than leaving a locked game")
	controller.rules["random_event_chance"] = 0.0


func _test_reshuffle_and_retention() -> void:
	var sim := _prepare()
	await _wait()
	sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
		"scope": "special", "target": "policy_reserve", "duration": -1,
	}}), sim.state, sim.rng)
	var reserve := StatusRules.find_modifier(sim.state, &"policy_reserve")
	reserve.ready_turn = sim.state.turn
	sim.state.hand.assign([&"starter_training", &"starter_small_business"])
	sim.state.deck.clear()
	sim.state.discard.assign([&"starter_infrastructure", &"starter_infrastructure", &"example_card", &"starter_small_business", &"starter_training"])
	ui._render()
	for frame in 6:
		await process_frame
	ui._dispatch(Command.end_turn())
	_expect(sim.state.flags.get("pending_retain", false) and not ui._settlement_active, "Retention is chosen before ending the turn")
	ui._dispatch(Command.choose_retained_card(0))
	await _wait()
	_expect(sim.state.hand.size() == 6 and sim.state.hand[0] == &"starter_training", "Retained card remains alongside five new draws")
	_expect(ui._pile_motion.get_child_count() == 0, "Reshuffle visuals leave no ghosts")


func _test_once_only_card_is_not_discarded() -> void:
	var sim := _prepare()
	await _wait()
	sim.state.hand.assign([&"starter_efficiency", &"starter_training"])
	sim.state.budget = 50
	sim.state.political_capital = 10
	ui._render()
	for frame in 6:
		await process_frame
	ui._dispatch(Command.play_card(&"starter_efficiency"))
	ui._dispatch(Command.end_turn())
	var end := Time.get_ticks_msec() + 7000
	while ui._settlement_active and Time.get_ticks_msec() < end:
		for child in ui._pile_motion.get_children():
			if str(child.get_meta("direction", "")) == "discard":
				_expect(child.get_meta("card_id", &"") != &"starter_efficiency", "An enacted one-time reform is removed, not flown into discard")
		await process_frame
	await _wait()
	_expect(not sim.state.discard.has(&"starter_efficiency"), "Animation never restores an enacted reform")
	# Cancelling/restarting during a draw must not leave temporary cards behind.
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	_expect(ui._pile_motion_active, "A restarted opening draw begins normally")
	ui.setup(controller, &"example_country")
	await create_timer(0.8).timeout
	_expect(not ui._pile_motion_active and ui._pile_motion.get_child_count() == 0, "Restart cancels previous draw animations cleanly")


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	ui = GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _test_start_and_draw()
	await _test_discard_and_redraw_same_card()
	await _test_end_turn_reward()
	await _test_reshuffle_and_retention()
	await _test_once_only_card_is_not_discarded()
	var audio := SfxAudio.ensure(ui)
	ui.free()
	controller.free()
	audio.free()
	await create_timer(0.15).timeout
	print("CARD PILE ANIMATION TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
