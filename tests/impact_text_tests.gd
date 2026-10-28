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
	for frame in 10:
		await process_frame


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory.path_join(filename))


func _run() -> void:
	var example := "3 回合内 潜在增长 +0.625；信心 -2；GDP +1.5%；抽两张牌 [说明]"
	var styled := ImpactText.create(example)
	styled.custom_minimum_size.x = 500
	root.add_child(styled)
	await _settle()
	_expect(styled.get_parsed_text() == example, "Highlighting preserves original text and literal brackets")
	_expect(styled.text.contains("[b]+0.625[/b]") and styled.text.contains("[b]-2[/b]") and styled.text.contains("[b]+1.5%[/b]"), "Signed decimals and percentages are emphasized")
	_expect(styled.text.contains("[b]两[/b]"), "Chinese numeric effect counts are emphasized")
	_expect(styled.get_theme_font("bold_font") == ImpactText.NUMBER_FONT, "Emphasized values use the bundled special bold numeric font")
	_expect(ImpactText.NUMBER_FONT.variation_opentype.get("wght") == 700.0, "The numeric font uses real 700 weight")
	var markup := ImpactText.highlight_bbcode("[color=#e5484d]信心 -2[/color]")
	_expect(markup.begins_with("[color=#e5484d]") and markup.contains("[b]-2[/b]"), "Existing markup/color codes are never mistaken for effect values")
	styled.free()
	var main = load("res://presentation/main.tscn").instantiate()
	root.add_child(main)
	main.controller.rules["random_event_chance"] = 0.0
	main._on_start_requested(&"arcadia")
	var ui: GameUI = main._screen
	ui._dispatch(Command.choose_reward([]))
	var sim: Simulation = main.controller.simulation
	sim.state.budget = 100
	sim.state.political_capital = 10
	sim.state.hand.assign([&"arcadia_relief_dole", &"starter_infrastructure", &"reform_project_continuity", &"route_construction_key_projects"])
	ui._render()
	await _settle()
	for button in ui._hand_box.get_children():
		var effects := button.find_child("Effects", true, false) as ImpactText
		_expect(effects != null and effects.text.contains("[b]"), "Every card effect block emphasizes its numeric data")
		_expect(button.get_global_rect().grow(1).encloses(effects.get_global_rect()), "Styled effects remain inside their card")
		var fee: Label = button.find_child("BudgetAmount", true, false).get_node("Amount")
		_expect(fee.get_theme_font("font") == ImpactText.NUMBER_FONT and fee.get_theme_color("font_color") == ImpactText.GOLD, "Card costs share gold bold numeric styling")
	var captured := EffectFeedback.capture(ui._hand_box.get_child(0))
	_expect(captured["tokens"].size() == 1 and captured["tokens"][0]["text"] == "+5", "Number-flight origins still work with rich effect text")
	_expect(ui._forecast.text.contains("[color=#%s]" % UiTheme.POSITIVE.to_html(false)), "Forecast green/red cues are preserved, not all replaced with gold")
	await _capture("fincard-gold-card-values.png")
	var definition: EconomyEventDef = main.controller.events[&"arcadia_ev_bank_panic"]
	sim._fire_event(definition.id)
	ui._render()
	await _settle()
	var choice: Button = ui._overlay_box.get_child(2)
	_expect(choice.find_children("*", "RichTextLabel", true, false).size() > 0, "Event-choice numeric effects use rich text without changing button actions")
	await _capture("fincard-gold-event-values.png")
	var audio := SfxAudio.ensure(main)
	main.free()
	audio.free()
	await create_timer(0.12).timeout
	print("IMPACT TEXT TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
