extends SceneTree

var failures := 0
var controller: GameController
var ui: GameUI
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


func _badge(key: String) -> Button:
	for child in ui._effect_icons.get_children():
		if str(child.get_meta("effect_key", "")) == key:
			return child
	return null


func _apply(params: Dictionary) -> void:
	var sim := controller.simulation
	ui._apply_command_events(sim.resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": params}), sim.state, sim.rng))


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	ui = GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	while ui._pile_motion_active:
		await process_frame
	var sim := controller.simulation
	sim.state.modifiers.clear()
	sim.state.turn = 10
	ui._modifier_recency.clear()
	ui._render()
	for badge in ui._effect_icons.get_children():
		_expect(not badge.get_meta("recent_change"), "Unmodified base parameters are not new effects")
	_apply({"scope": "coefficient", "target": "gdp_auto", "value": 0.4, "duration": 3, "source": "investment"})
	_expect(ui._effect_icons.get_child(0).get_meta("effect_key") == "coefficient:gdp_auto", "Newest investment moves to the far-left slot")
	_expect(_badge("coefficient:gdp_auto").get_meta("recent_change") and _badge("coefficient:gdp_auto").tooltip_text.contains("本回合更新"), "Current changes are highlighted and identified in the tooltip")
	_apply({"scope": "fiscal", "target": "annual_income", "value": 4, "duration": -1, "source": "income"})
	_expect(ui._effect_icons.get_child(0).get_meta("effect_key") == "fiscal:annual_income", "A later change is placed before earlier ones")
	_apply({"scope": "coefficient", "target": "gdp_auto", "value": 0.2, "duration": 2, "source": "investment2"})
	_expect(ui._effect_icons.get_child(0).get_meta("effect_key") == "coefficient:gdp_auto", "A changed existing aggregate returns to the left")
	var previous_order := int(_badge("coefficient:gdp_auto").get_meta("change_order"))
	var current_color: Color = _badge("coefficient:gdp_auto").get_theme_stylebox("normal").bg_color
	var node_id := _badge("coefficient:gdp_auto").get_instance_id()
	ui._render()
	_expect(_badge("coefficient:gdp_auto").get_instance_id() == node_id, "An unchanged redraw reuses the badge")
	sim.state.turn = 11
	ui._render()
	_expect(_badge("coefficient:gdp_auto").get_meta("recent_change") and _badge("coefficient:gdp_auto").tooltip_text.contains("上回合更新"), "Last-turn changes remain highlighted")
	_expect(_badge("coefficient:gdp_auto").get_theme_stylebox("normal").bg_color != current_color, "Current and previous-turn highlights are visually distinct")
	var original_modifiers := sim.state.modifiers.duplicate()
	sim._advance_modifiers()
	ui._render()
	_expect(int(_badge("coefficient:gdp_auto").get_meta("change_order")) == previous_order, "Ordinary duration countdown never refreshes recency")
	sim.state.turn = 12
	ui._render()
	_expect(not _badge("coefficient:gdp_auto").get_meta("recent_change"), "Highlight expires after current/previous turns")
	var modifier: Modifier = original_modifiers[0]
	modifier.stacks += 1
	ui._render()
	_expect(_badge("coefficient:gdp_auto").get_meta("recent_change") and int(_badge("coefficient:gdp_auto").get_meta("changed_turn")) == 12, "A stack change is detected even without a UI event")
	_apply({"scope": "special", "target": "project_continuity", "duration": -1})
	_expect(ui._effect_icons.get_child(0).get_meta("effect_key") == "special:project_continuity", "A newly acquired delayed reform is newest")
	_apply({"scope": "fiscal", "target": "budget_retention", "value": 0.25, "duration": -1})
	sim.state.turn = 13
	ui._render()
	_expect(ui._effect_icons.get_child(0).get_meta("effect_key") == "special:project_continuity", "A reform becoming active at turn start is a new change")
	var history_order := int(_badge("special:project_continuity").get_meta("change_order"))
	StatusRules.find_modifier(sim.state, &"project_continuity").data["triggered_turn"] = 13
	ui._render()
	_expect(int(_badge("special:project_continuity").get_meta("change_order")) == history_order, "Routine trigger/progress bookkeeping does not reorder the bar")
	if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join("fincard-recent-modifiers.png"))
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	while ui._pile_motion_active:
		await process_frame
	_expect(_badge("special:project_continuity") == null and _badge("fiscal:annual_income") == null, "New games clear old modifier recency history")
	var audio := SfxAudio.ensure(ui)
	ui.free()
	controller.free()
	audio.free()
	await create_timer(0.15).timeout
	print("MODIFIER RECENCY TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
