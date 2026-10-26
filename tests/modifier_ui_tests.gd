extends SceneTree

var failures: int = 0
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


func _entry(entries: Array[Dictionary], key: String) -> Dictionary:
	for entry in entries:
		if entry["key"] == key:
			return entry
	_expect(false, "Missing display entry: %s" % key)
	return {}


func _run() -> void:
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
	sim.state.modifiers.clear()
	var modifiers: Array[Modifier] = [
		Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.1, -1, &"来源甲", &"coefficient"),
		Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.4, 2, &"来源乙", &"coefficient"),
		Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.2, 4, &"来源丙", &"coefficient"),
		Modifier.new(&"annual_income", Modifier.Op.ADD, 4, -1, &"来源丁", &"fiscal"),
		Modifier.new(&"annual_income", Modifier.Op.ADD, 6, 2, &"来源戊", &"fiscal"),
		Modifier.new(&"interest_rate", Modifier.Op.ADD, -100, 1, &"来源己"),
	]
	sim.state.modifiers.assign(modifiers)
	sim.state.statuses.assign([&"deficit_spending", &"executive_mandate"])
	var entries := ModifierDisplay.entries(sim, controller.labels)
	_expect(entries.size() == sim.economy.base_coefficients.size() + 4, "Three base parameters plus acquired effects share one entry list")
	var growth := _entry(entries, "coefficient:gdp_auto")
	_expect(growth["counter"] == "+0.7", "Same target combines temporary and permanent values")
	_expect("2 回合后：合计 +0.3" in growth["tooltip"] and "4 回合后：合计 +0.1" in growth["tooltip"], "Hover presents merged expiry results, never individual sources")
	var income := _entry(entries, "fiscal:annual_income")
	_expect(income["counter"] == "+10" and "2 次财年发放后：合计 +4" in income["tooltip"], "Fiscal expiry uses annual payments")
	_expect(_entry(entries, "indicator:interest_rate")["counter"] == "-3", "Display uses clamped effective result, not sum of raw values")
	for entry in entries:
		_expect(not "来源" in entry["tooltip"], "Merged tooltips must not list sources")
	_expect(modifiers[1].remaining_turns == 2 and sim.state.modifiers.size() == 6, "Display cannot modify simulation stacks or durations")
	# Mixed operations preserve simulation order instead of summing incompatible values.
	sim.state.modifiers.assign([
		Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.2, -1, &"", &"coefficient"),
		Modifier.new(&"gdp_auto", Modifier.Op.MUL, 2, -1, &"", &"coefficient"),
		Modifier.new(&"gdp_auto", Modifier.Op.OVERRIDE, 1, 1, &"", &"coefficient"),
		Modifier.new(&"gdp_auto", Modifier.Op.ADD, 0.3, -1, &"", &"coefficient"),
	])
	var mixed := _entry(ModifierDisplay.entries(sim, controller.labels), "coefficient:gdp_auto")
	_expect(mixed["counter"] == "+1.12", "Add, multiply, override and subsequent add use actual operation order")
	_expect("1 回合后：合计 +0.88" in mixed["tooltip"], "Expiry recomputes remaining operations in order")
	sim.state.modifiers.assign(modifiers)
	ui._render()
	for i in 5:
		await process_frame
	_expect(ui._effect_icons.get_child_count() == entries.size(), "UI renders one badge per parameter or merged effect including abilities")
	for i in ui._effect_icons.get_child_count():
		var badge: Button = ui._effect_icons.get_child(i)
		_expect(badge.get_theme_color("font_color") == UiTheme.modifier_color(i), "Badge color depends only on display index")
		if i > 0:
			_expect(badge.get_theme_color("font_color") != ui._effect_icons.get_child(i - 1).get_theme_color("font_color"), "Neighboring badges have staggered colors")
	_expect(ui._log.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "Unified bar cannot overflow main layout")
	var original_color: Color = ui._effect_icons.get_child(0).get_theme_color("font_color")
	sim.state.modifiers.reverse()
	ui._render()
	_expect(ui._effect_icons.get_child(0).get_meta("effect_key") == "indicator:interest_rate", "First occurrence defines stable group order")
	_expect(ui._effect_icons.get_child(0).get_theme_color("font_color") == original_color, "Changing type at the same index keeps the color")
	sim.state.modifiers.assign(modifiers)
	sim._advance_modifiers()
	sim._advance_modifiers()
	var after := ModifierDisplay.entries(sim, controller.labels)
	_expect(_entry(after, "coefficient:gdp_auto")["counter"] == "+0.3", "Expired temporary contribution disappears while permanent contribution stays")
	_expect(_entry(after, "fiscal:annual_income")["counter"] == "+10", "Monthly expiry does not consume fiscal duration")
	ui._render()
	for i in 4:
		await process_frame
	if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(capture_directory.path_join("fincard-unified-modifiers.png")) == OK, "Unified modifier screenshot saves")
	sim.state.modifiers.clear()
	sim.state.statuses.clear()
	ui._render()
	_expect(ui._effect_icons.get_child_count() == 3, "Only three base parameters remain without acquired effects")
	ui.free()
	controller.free()
	print("MODIFIER UI TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
