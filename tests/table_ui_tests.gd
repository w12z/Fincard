extends SceneTree

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


func _settle() -> void:
	for i in 6:
		await process_frame


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(capture_directory.path_join(filename)) == OK, "Table screenshot must save")


func _check_resource_icons(ui: GameUI) -> void:
	for resource in ["BudgetAmount", "PoliticalAmount"]:
		var balance: ResourceAmount = ui._header.get_node(resource)
		_expect(balance.get_node("Icon").texture != null and not balance.tooltip_text.is_empty(), "Resource balances need an icon and a named tooltip")
		_expect(root.get_visible_rect().encloses(balance.get_global_rect()), "Resource balances must fit the viewport")
	for button in ui._hand_box.get_children():
		if not button is Button:
			continue
		_expect(button.text.is_empty(), "Hand uses structured content rather than text resource names")
		for resource in ["BudgetAmount", "PoliticalAmount"]:
			var fee: ResourceAmount = button.find_child(resource, true, false)
			_expect(fee != null and fee.get_node("Icon").texture != null, "Each card needs both resource icons, including zero costs")
			_expect(button.get_global_rect().grow(1).encloses(fee.get_global_rect()), "Costs and original prices must stay inside their card")
			_expect(fee.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Cost widgets must not intercept card clicks")
		var content: VBoxContainer = button.get_child(0).get_child(0)
		for child in content.get_children():
			_expect(button.get_global_rect().grow(1).encloses(child.get_global_rect()), "Hand content must wrap within the card")


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
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	for cabinet: CabinetDef in controller.cabinets.values():
		sim._appoint_cabinet(cabinet.id)
	for id in controller.statuses:
		sim.resolver.resolve(Effect.from_dict({"kind": "grant_status", "params": {"status": id}}), sim.state, sim.rng)
	for id in controller.aids:
		sim._gain_aid(id)
	sim.state.budget = 100
	sim.state.political_capital = 30
	sim.state.hand.assign([&"starter_small_business", &"starter_infrastructure", &"reform_executive_mandate", &"starter_training", &"starter_infrastructure", &"example_card"])
	ui._render()
	await _settle()
	var cabin_rect := ui._cabinet_bar.get_global_rect()
	_expect(ui._statuses_box.global_position.x >= cabin_rect.end.x, "Reform abilities belong to the right of the cabinet")
	_expect(ui._aids_box.global_position.x > ui._statuses_box.global_position.x, "Aid controls belong in the upper-right corner")
	_expect(ui._aids_box.global_position.y < ui._played_table.global_position.y, "Aid controls must remain above the table")
	_expect(ui._hand_scroll.global_position.y > root.size.y * 0.5, "Hand must be placed at the bottom")
	_expect(ui._played_table.get_global_rect().end.y <= ui._hand_scroll.global_position.y, "Played cards must appear above the hand")
	_expect(ui._played_table._cards.is_empty(), "A new turn must open with an empty table")
	_expect(root.get_visible_rect().encloses(cabin_rect), "Top panels must fit the viewport")
	var aid: Button = ui._aids_box.get_child(0)
	_expect(not aid.disabled and "×" in aid.text and not aid.tooltip_text.is_empty(), "Aid buttons need remaining uses and hover details")
	var hand_card: Button = ui._hand_box.get_child(0)
	_check_resource_icons(ui)
	_expect(ui._header.get_node("BudgetAmount/Icon").texture != ui._header.get_node("PoliticalAmount/Icon").texture, "Budget and political points use distinct artwork")
	_expect(not hand_card.disabled and hand_card.find_child("PoliticalAmount", true, false).get_node("Amount").text.begins_with("0"), "Bottom hand must preserve discounted costs")
	hand_card.pressed.emit()
	_expect(sim.state.played_cards_this_turn == [&"starter_small_business"], "Successful hand clicks must enter the table history")
	aid = ui._aids_box.get_child(0)
	aid.pressed.emit()
	_expect(sim.state.played_cards_this_turn.size() == 1, "Aid use must not add a card to the table")
	for id in [&"starter_infrastructure", &"reform_executive_mandate", &"starter_training"]:
		ui._dispatch(Command.play_card(id))
	await _settle()
	var expected: Array[StringName] = [&"starter_small_business", &"starter_infrastructure", &"reform_executive_mandate", &"starter_training"]
	_expect(sim.state.played_cards_this_turn == expected, "Played cards must retain exact play order")
	_expect(ui._played_table._cards.size() == 4, "Every successful play needs one table card")
	for i in ui._played_table._cards.size():
		var card: Button = ui._played_table._cards[i]
		_expect(card.get_meta("card_id") == expected[i] and card.get_meta("play_order") == i + 1, "Table order must match history")
		_expect(root.get_visible_rect().encloses(card.get_global_rect()), "Played cards must fit the table")
		if i > 0:
			var previous: Button = ui._played_table._cards[i - 1]
			_expect(card.position.x > previous.position.x and card.position.x < previous.position.x + previous.size.x, "Played cards must overlap in left-to-right order")
	var first: Button = ui._played_table._cards[0]
	first.mouse_entered.emit()
	_expect(first.z_index > ui._played_table._cards.back().z_index, "Hovering an older card must raise it above the stack")
	first.mouse_exited.emit()
	_expect(first.z_index == 1, "Leaving a card must restore stack order")
	ui._render()
	_expect(ui._played_table._cards.size() == 4, "Redrawing the UI must not duplicate played cards")
	sim.state.budget = 0
	sim.state.political_capital = 0
	ui._dispatch(Command.play_card(&"starter_infrastructure"))
	_expect(sim.state.played_cards_this_turn == expected, "Failed attempts must not enter table history")
	_expect(ui._hand_box.get_child(0).disabled, "Unaffordable hand cards must remain disabled")
	sim.state.budget = 50
	sim.state.political_capital = 20
	ui._render()
	await _settle()
	await _capture("fincard-card-table.png")
	# Long hands and long play sequences scroll rather than widening the viewport.
	sim.state.hand.clear()
	for i in 20:
		sim.state.hand.append(&"starter_small_business")
	sim.state.budget = 200
	sim.state.political_capital = 100
	ui._render()
	await _settle()
	_expect(ui._hand_scroll.get_h_scroll_bar().max_value > ui._hand_scroll.size.x, "Long hands must scroll horizontally")
	for i in 18:
		ui._dispatch(Command.play_card(&"starter_small_business"))
	await _settle()
	_expect(sim.state.played_cards_this_turn.size() == 22, "Repeated copies must each have their own history entry")
	var table_scroll: ScrollContainer = ui._played_table.get_parent()
	_expect(table_scroll.scroll_horizontal > 0, "Long play sequences must scroll to the newest card")
	_expect(ui._log.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "Long card rows must not expand the whole UI")
	await _capture("fincard-card-table-long.png")
	ui._dispatch(Command.end_turn())
	_expect(sim.state.played_cards_this_turn.is_empty() and ui._played_table._cards.is_empty(), "A new turn must clear the table")
	# The top and bottom action areas must stay accessible at a smaller window size.
	var original_size := root.size
	root.size = Vector2i(1280, 800)
	await _settle()
	_expect(root.get_visible_rect().encloses(ui._cabinet_bar.get_global_rect()), "Cabinet must remain in bounds at 1280x800")
	_expect(ui._aids_box.global_position.x < root.get_visible_rect().end.x, "Aid controls must remain accessible at 1280x800")
	_expect(root.get_visible_rect().encloses(ui._end_turn_button.get_global_rect()), "Bottom actions must remain in bounds at 1280x800")
	_expect(ui._log.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "Smaller windows must not overflow horizontally")
	_check_resource_icons(ui)
	await _capture("fincard-resource-icons-small.png")
	root.size = original_size
	await _settle()
	# A new run must clear history even after a directly dispatched play.
	sim.state.hand.assign([&"starter_small_business"])
	sim.state.budget = 10
	sim.state.political_capital = 10
	sim.apply_command(Command.play_card(&"starter_small_business"))
	_expect(not sim.state.played_cards_this_turn.is_empty(), "Simulation must track plays independently of the UI")
	sim.start_run(&"example_country")
	_expect(sim.state.played_cards_this_turn.is_empty(), "Starting a new run must clear table history")
	ui.free()
	controller.free()
	await process_frame
	print("TABLE UI TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
