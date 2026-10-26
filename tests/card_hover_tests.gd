extends SceneTree

var failures := 0
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


func _settle() -> void:
	for i in 6:
		await process_frame


func _check_preview(button: Control, budget: String, political: String) -> void:
	var preview: Control = button._make_custom_tooltip(button.tooltip_text)
	_expect(preview.find_child("BudgetAmount", true, false).get_node("Amount").text == budget, "Hover preview includes budget and original cost when discounted")
	_expect(preview.find_child("PoliticalAmount", true, false).get_node("Amount").text == political, "Hover preview includes political cost, even when zero")
	var description: Label = preview.find_child("Description", true, false)
	_expect(description.text == button.tooltip_text.substr(button.tooltip_text.find("\n") + 1), "Cost preview retains full card details and effects after its structured heading")
	_expect(preview.find_child("CardName", true, false).text == button.preview_card.display_name, "Preview heading retains the card name")
	preview.free()


func _run() -> void:
	root.gui_embed_subwindows = true
	var controller := GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	var rewards_checked := 0
	for choice in ui._overlay_box.get_children():
		if choice is CardPreview.RewardChoice and choice.is_card:
			_check_preview(choice, choice.preview_budget, choice.preview_political)
			rewards_checked += 1
	_expect(rewards_checked > 0, "Annual card choices include cost previews")
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	sim.resolver.resolve(Effect.from_dict({"kind": "grant_status", "params": {"status": "earmarked_funds"}}), sim.state, sim.rng)
	sim.resolver.resolve(Effect.from_dict({"kind": "grant_status", "params": {"status": "executive_mandate"}}), sim.state, sim.rng)
	sim.state.budget = 50
	sim.state.political_capital = 20
	sim.state.hand.assign([&"starter_small_business", &"starter_infrastructure"])
	ui._render()
	await _settle()
	var card: CardButton = ui._hand_box.get_child(0)
	var costs := sim.card_costs(&"starter_small_business")
	var definition: CardDef = controller.cards[&"starter_small_business"]
	var budget := str(costs["budget"])
	if int(costs["budget"]) != definition.cost:
		budget += "（原%d）" % definition.cost
	var political := str(costs["political"])
	if int(costs["political"]) != definition.political_cost:
		political += "（原%d）" % definition.political_cost
	_check_preview(card, budget, political)
	var slot := card.get_global_rect()
	card.mouse_entered.emit()
	_expect(is_zero_approx(card._face.offset_top), "Hover lift starts from its resting position, not an instant jump")
	await create_timer(0.06).timeout
	_expect(card._face.offset_top < 0 and card._face.offset_top > -CardButton.LIFT, "Hover moves the card gradually")
	await create_timer(0.2).timeout
	_expect(is_equal_approx(card._face.offset_top, -CardButton.LIFT), "Playable card lifts slightly on hover")
	_expect(card.get_global_rect() == slot, "Hover must not move layout slots or disturb neighboring cards")
	_expect(card._has_point(Vector2(10, card.size.y - 1)) and card._has_point(Vector2(10, -5)), "Both original and raised edges remain clickable without hover jitter")
	_expect(ui._hand_scroll.get_global_rect().encloses(card._face.get_global_rect()), "Lifted card is not clipped by its scrolling viewport")
	card.mouse_exited.emit()
	await create_timer(0.2).timeout
	_expect(is_zero_approx(card._face.offset_top) and is_zero_approx(card._face.offset_bottom), "Leaving restores the full card to its original position")
	card.mouse_entered.emit()
	await create_timer(0.04).timeout
	card.mouse_exited.emit()
	await create_timer(0.2).timeout
	_expect(is_zero_approx(card._face.offset_top), "Rapid enter/leave cancels the old tween and returns cleanly")
	card.mouse_entered.emit()
	await create_timer(0.2).timeout
	if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
		# Show the exact custom tooltip content in a deterministic embedded popup.
		var popup := PopupPanel.new()
		popup.theme = ui.theme
		popup.add_child(card._make_custom_tooltip(card.tooltip_text))
		root.add_child(popup)
		popup.popup(Rect2i(Vector2i(card.global_position) - Vector2i(0, 260), Vector2i(380, 220)))
		card.mouse_entered.emit()
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(capture_directory.path_join("fincard-card-hover.png")) == OK, "Hover screenshot saves")
		popup.free()
	card.pressed.emit()
	_expect(sim.state.played_cards_this_turn == [&"starter_small_business"], "Raised cards remain playable")
	await _settle()
	var played: CardButton = ui._played_table._cards[0]
	_check_preview(played, str(definition.cost), str(definition.political_cost))
	sim.state.budget = 0
	sim.state.political_capital = 0
	ui._render()
	await _settle()
	card = ui._hand_box.get_child(0)
	_expect(card.disabled, "Unfunded card is disabled")
	card.mouse_entered.emit()
	await create_timer(0.2).timeout
	_expect(is_zero_approx(card._face.offset_top), "Disabled cards never lift on hover")
	_check_preview(card, card.preview_budget, card.preview_political)
	ui.free()
	controller.free()
	await process_frame
	print("CARD HOVER TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
