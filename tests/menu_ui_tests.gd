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
	for i in 4:
		await process_frame


func _check_copy(node: Node) -> void:
	var text := ""
	if node is Label or node is BaseButton or node is RichTextLabel:
		text = node.text
	if node is Control:
		text += "\n" + node.tooltip_text
	for phrase in ["书写下一段繁荣", "力挽狂澜", "了解这片土地", "每一次选择", "请检查剧本数据", "向下滚动", "无需点击", "通过特殊改革，可改变", "示例内阁", "示例预算", "示例援助", "政府债务", "债务率", "税率", "资金收支直接计入", "每个候选先按", "从下次生成奖励起生效", "预算成本不变", "政治成本不变", "不免除政治成本"]:
		_expect(not phrase in text, "Obsolete player-facing copy: %s" % phrase)
	for child in node.get_children():
		_check_copy(child)


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(capture_directory.path_join(filename))
	_expect(error == OK, "Screenshot failed")


func _run() -> void:
	var main = load("res://presentation/main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	_expect(main._screen is ScenarioMenu, "Game must open on the country selection screen")
	var menu: ScenarioMenu = main._screen
	_expect(menu._list.get_child_count() == main.controller.scenarios.size(), "Every country needs a selection card")
	_expect(menu._list.columns == 2, "Wide menu must use two columns")
	_check_copy(menu)
	for card: Button in menu._list.get_children():
		_expect(root.get_visible_rect().encloses(card.get_global_rect()), "Country cards must fit the viewport")
	await _capture("fincard-country-menu.png")
	var first := CountryFlag.new()
	var second := CountryFlag.new()
	first.setup(&"example_country")
	second.setup(&"example_country")
	_expect(first._colors == second._colors and first._pattern == second._pattern and first._emblem == second._emblem, "Flags must stay consistent across screens")
	first.free()
	second.free()
	for id in [&"example_country", &"arcadia"]:
		menu = main._screen
		# Exercise the actual button callback, not just the main routing method.
		var index := 0 if id == &"example_country" else 1
		menu._list.get_child(index).pressed.emit()
		await _settle()
		_expect(main._screen is CountryProfile, "Clicking a country must open its profile")
		var profile: CountryProfile = main._screen
		_expect(profile.scenario.id == id, "Profile must match the selected country")
		_check_copy(profile)
		_expect(main.controller.simulation.state.scenario_id == &"", "Reading a profile must not start a run")
		_expect(root.get_visible_rect().encloses(profile._confirm_button.get_global_rect()), "Confirm button must remain on screen")
		_expect(root.get_visible_rect().encloses(profile._back_button.get_global_rect()), "Back button must remain on screen")
		await _capture("fincard-profile-%s.png" % id)
		if id == &"arcadia":
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			profile._unhandled_key_input(escape)
		else:
			profile._back_button.pressed.emit()
		await _settle()
		_expect(main._screen is ScenarioMenu, "Back must return to the selection screen")
		_expect(main.controller.simulation.state.pending_rewards.is_empty(), "Back must not initialize a run")
	# Small layouts stack rather than hide country information.
	menu = main._screen
	menu.size.x = 900
	menu._update_columns()
	_expect(menu._list.columns == 1, "Narrow menu must stack country cards")
	menu.country_selected.emit(&"arcadia")
	await _settle()
	var profile: CountryProfile = main._screen
	profile.size.x = 900
	profile._update_columns()
	_expect(profile._columns.vertical, "Narrow profile must stack its panels")
	profile._confirm_button.pressed.emit()
	await _settle()
	_expect(main._screen is GameUI, "Confirm must enter the game")
	_expect(main.controller.simulation.state.scenario_id == &"arcadia", "Confirm must start the selected scenario")
	_expect(not main.controller.simulation.state.pending_rewards.is_empty(), "A confirmed run must begin with annual preparation")
	_check_copy(main._screen)
	main.free()
	await process_frame
	print("MENU UI TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
