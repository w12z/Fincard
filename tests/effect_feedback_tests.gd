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
	for frame in 6:
		await process_frame


func _run() -> void:
	var controller := GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	_expect(EconomyForecast.change_color(sim, &"gdp", 100, 102) == UiTheme.POSITIVE, "GDP gains are green")
	_expect(EconomyForecast.change_color(sim, &"gdp", 102, 100) == UiTheme.NEGATIVE, "GDP losses are red")
	_expect(EconomyForecast.change_color(sim, &"unemployment", 7, 5) == UiTheme.POSITIVE, "Unemployment decreases are green")
	_expect(EconomyForecast.change_color(sim, &"unemployment", 5, 7) == UiTheme.NEGATIVE, "Unemployment increases are red")
	_expect(EconomyForecast.change_color(sim, &"confidence", 50, 52) == UiTheme.POSITIVE, "Confidence gains are green")
	_expect(EconomyForecast.change_color(sim, &"inflation", 4, 3) == UiTheme.POSITIVE, "Inflation moving toward target is green")
	_expect(EconomyForecast.change_color(sim, &"inflation", 0, -1) == UiTheme.NEGATIVE, "Worsening deflation is red despite decreasing inflation")
	_expect(EconomyForecast.change_color(sim, &"interest_rate", 3, 4) == UiTheme.MUTED, "Interest rate trade-offs remain neutral")
	_expect(EconomyForecast.change_color(sim, &"gdp", 100, 100) == UiTheme.MUTED, "Unchanged indicators remain neutral")
	var forecast := EconomyForecast.text(sim, controller.labels, false)
	_expect(forecast.contains("[color=#%s]+" % UiTheme.POSITIVE.to_html(false)), "Forecast colors the signed delta with BBCode")
	var card := CardDef.from_dict({"id": "feedback_probe", "display_name": "反馈测试", "card_type": "policy", "cost": 0, "political_cost": 0,
		"effects": [
			{"kind": "adjust_indicator", "params": {"target": "confidence", "amount": 2}},
			{"kind": "apply_modifier", "params": {"scope": "coefficient", "target": "gdp_auto", "value": 0.4, "duration": 3, "source": "反馈测试"}},
		]})
	controller.cards[card.id] = card
	sim.state.hand.assign([card.id])
	ui._render()
	await _settle()
	var button: CardButton = ui._hand_box.get_child(0)
	var origin := EffectFeedback.capture(button)
	_expect(origin["tokens"].size() == 2, "Capture individual +2 and +0.4 numeric glyphs from the original card")
	var original_confidence := float(sim.state.indicators[&"confidence"])
	var no_change := [Event.new(Event.Kind.CARD_PLAYED, {"card_id": card.id}),
		Event.new(Event.Kind.INDICATOR_CHANGED, {"indicator": &"confidence", "delta": 0, "previous": 100, "current": 100})]
	_expect(EffectFeedback.cues(no_change, sim).is_empty(), "Clamped zero changes must not create fake +2 feedback")
	button.pressed.emit()
	await create_timer(0.38).timeout
	await _settle()
	_expect(sim.state.indicators[&"confidence"] == original_confidence + 2, "Animation does not resolve an effect twice")
	_expect(ui._effect_feedback.get_child_count() == 2, "One number flies for each actual card effect")
	var keys: Array = []
	for number in ui._effect_feedback.get_children():
		keys.append(str(number.get_meta("effect_key", "")))
		_expect(number.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Flying numbers never block input")
	_expect(keys.has("indicator:confidence") and keys.has("coefficient:gdp_auto"), "Immediate effects and modifiers go to different destinations")
	_expect(ui._effect_feedback_target("indicator:confidence") != ui._effect_feedback_target("coefficient:gdp_auto", true), "Indicator and modifier destinations must not be confused")
	_expect(ui._effect_feedback_target("indicator:interest_rate", true) != ui._effect_feedback_target("indicator:interest_rate"), "Persistent interest-rate modifiers fly to the upper strip, not the instantaneous indicator row")
	if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join("fincard-effect-flight.png"))
	await create_timer(1.0).timeout
	await _settle()
	_expect(ui._effect_feedback.get_child_count() == 0, "Flying numbers and destination pulses clean themselves up")
	# A turn change cancels old effects without leaving ghosts.
	sim.state.hand.assign([card.id])
	ui._render()
	await _settle()
	ui._dispatch(Command.play_card(card.id))
	await _settle()
	_expect(ui._effect_feedback.get_child_count() > 0, "Direct dispatch also produces effect feedback")
	ui._dispatch(Command.end_turn())
	while ui._settlement_active:
		await process_frame
	await _settle()
	_expect(ui._effect_feedback.get_child_count() == 0, "New turns remove all old effect animations")
	ui.free()
	controller.free()
	await process_frame
	print("EFFECT FEEDBACK TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
