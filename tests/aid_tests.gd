extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare() -> Simulation:
	var sim := controller.simulation
	sim.start_run(&"arcadia")
	sim.apply_command(Command.choose_reward([]))
	return sim


func _test_capacity() -> void:
	var sim := _prepare()
	_expect(sim.aid_capacity() == 3 and sim.aid_count() == 0, "Aid capacity is three independent items")
	var events := sim._gain_aid(&"arcadia_aid_fireside")
	_expect(sim.aid_count() == 2 and sim.state.aids.size() == 2 and events[0].params["amount"] == 2, "Fireside grants two separate aid items")
	_expect(sim.aid_gain_amount(&"arcadia_aid_fireside") == 1, "Only one of the two offered bottles fits in the last slot")
	var reward := Reward.new(Reward.Type.AID, &"arcadia_aid_fireside", "")
	events = sim._grant_reward(reward)
	_expect(sim.aid_count() == 3 and sim.state.aids.size() == 3 and events[0].params["amount"] == 1, "Duplicate aid occupies its own slot and logs the actual gain")
	for id in sim.aid_db:
		_expect(sim._gain_aid(id).is_empty(), "Direct aid grants cannot bypass full capacity")
	_expect(sim._grant_reward(reward).is_empty() and sim.aid_count() == 3, "A stale reward cannot exceed capacity")
	for group in sim._build_year_end_rewards():
		_expect(group["type"] != Reward.Type.AID, "Full inventory suppresses the annual aid group")
	var played := sim.state.cards_played_this_turn
	sim.apply_command(Command.use_aid(&"arcadia_aid_fireside"))
	_expect(sim.aid_count() == 2 and sim.state.cards_played_this_turn == played, "Using aid frees exactly one slot and does not count as a card")
	_expect(sim._reward_available(Reward.Type.AID, &"arcadia_aid_gold"), "A freed slot re-enables aid rewards")
	sim._gain_aid(&"arcadia_aid_gold")
	_expect(sim.aid_count() == 3 and sim.state.aids.size() == 3, "Different aid types share the same capacity")
	sim.apply_command(Command.use_aid(&"arcadia_aid_gold"))
	_expect(sim.aid_count() == 2 and sim.state.aids.size() == 2, "Using an aid removes exactly one independent item")
	sim.state.turn_in_year = int(sim.rules["turns_per_year"])
	sim._end_year()
	sim.apply_command(Command.choose_reward([]))
	_expect(sim.aid_count() == 2, "Remaining bottles persist across fiscal years")
	sim = _prepare()
	_expect(sim.aid_count() == 0, "Restart clears all aid bottles")
	sim._gain_aid(&"arcadia_aid_gold")
	sim._gain_aid(&"arcadia_aid_foreign_loan")
	sim._gain_aid(&"arcadia_aid_fireside")
	_expect(sim.aid_count() == 3 and sim.state.aids.size() == 3 and sim.state.aids[2]["uses"] == 1, "A new two-bottle aid is also truncated when only one slot remains")
	var preview := sim.forecast_next_turn()
	var uses := 0
	for entry in preview.aids:
		uses += int(entry["uses"])
	_expect(uses == 3 and sim.aid_count() == 3, "Forecast preserves aid inventory without mutation")
	sim.rules["aid_capacity"] = 0
	sim = _prepare()
	_expect(sim._gain_aid(&"arcadia_aid_fireside").is_empty(), "Zero configured capacity rejects aid grants")
	for group in sim._build_year_end_rewards():
		_expect(group["type"] != Reward.Type.AID, "Zero capacity omits aid rewards without blocking other groups")
	sim.rules["aid_capacity"] = 3


func _test_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	root.add_child(ui)
	ui.setup(controller, &"arcadia")
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	sim._gain_aid(&"arcadia_aid_fireside")
	ui._render()
	await process_frame
	_expect(ui._aids_title.text == "外部援助 2/3" and ui._aids_box.get_child_count() == 2, "Fireside is displayed as two independent aid buttons")
	var reward := Reward.new(Reward.Type.AID, &"arcadia_aid_fireside", "")
	_expect(ui._reward_detail(reward) == TextFormatter.effects_text(controller.labels, controller.aids[reward.id].effects), "Aid reward details show only effects")
	var button: Button = ui._aids_box.get_child(0)
	_expect(button.text == "炉边谈话" and button.tooltip_text == "炉边谈话\n" + TextFormatter.effects_text(controller.labels, controller.aids[reward.id].effects), "Aid buttons show only the name and effects")
	button.pressed.emit()
	_expect(sim.aid_count() == 1 and ui._aids_title.text == "外部援助 1/3", "Actual aid button consumes one bottle and refreshes capacity")
	ui.free()
	await process_frame


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_capacity()
	await _test_ui()
	controller.free()
	print("AID TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
