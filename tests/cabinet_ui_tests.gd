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
	for i in 5:
		await process_frame


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(capture_directory.path_join(filename)) == OK, "Cabinet screenshot must save")


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
	ui.setup(controller, &"arcadia")
	await _settle()
	_expect(ui._cabinets_box.get_child(0) is Label, "Empty cabinet must show a compact placeholder")
	await _settle()
	var candidates: Array[CabinetPortrait] = []
	_find_portraits(ui._overlay_box, candidates)
	_expect(not candidates.is_empty(), "Cabinet reward options need portraits")
	for candidate in candidates:
		var check: CheckBox = candidate.get_parent().get_child(1)
		candidate.pressed.emit()
		_expect(check.button_pressed, "Clicking a candidate portrait must select that cabinet")
		var group_index := _cabinet_group(controller.simulation.state)
		_expect(ui._reward_selection.has(group_index), "Portrait selection must update the reward command")
		if ui._reward_selection.has(group_index):
			var selected: Reward = controller.simulation.state.pending_rewards[group_index]["options"][ui._reward_selection[group_index]]
			_expect(selected.id == candidate.cabinet_id, "Every portrait must select its own candidate")
	await _capture("fincard-cabinet-rewards.png")
	ui._confirm_rewards()
	_expect(controller.simulation.state.cabinets.size() == 1, "Confirmed portrait choice must appoint a cabinet")
	for cabinet: CabinetDef in controller.cabinets.values():
		if not controller.simulation.state.cabinets.has(cabinet):
			controller.simulation._appoint_cabinet(cabinet.id)
	ui._render()
	await _settle()
	_expect(ui._cabinets_box.get_child_count() == controller.cabinets.size(), "Each cabinet needs exactly one portrait")
	_expect(ui._cabinet_bar.get_global_rect().end.y <= ui._hand_box.global_position.y, "Cabinets must sit above the main play area")
	_expect(root.get_visible_rect().encloses(ui._cabinet_bar.get_global_rect()), "Cabinet bar must fit the viewport")
	var paths := {}
	for badge: CabinetPortrait in ui._cabinets_box.get_children():
		var cabinet: CabinetDef = controller.cabinets[badge.cabinet_id]
		_expect(badge.text.is_empty(), "Relic bar must use portraits rather than text blocks")
		_expect(badge.portrait.texture != null, "Cabinet portrait asset missing: %s" % cabinet.id)
		if badge.portrait.texture != null:
			paths[badge.portrait.texture.resource_path] = true
		_expect(cabinet.display_name in badge.tooltip_text and cabinet.description in badge.tooltip_text, "Hover must include the cabinet identity and description")
		for effect in cabinet.modifiers:
			_expect(TextFormatter.effect_text(controller.labels, effect) in badge.tooltip_text, "Hover must include passive effects")
		for trigger in cabinet.triggers:
			_expect(TextFormatter.trigger_text(controller.labels, trigger) in badge.tooltip_text, "Hover must include triggered effects")
		_expect(root.get_visible_rect().encloses(badge.get_global_rect()), "All seven portraits must fit at default resolution")
		var tooltip: Control = badge._make_custom_tooltip(badge.tooltip_text)
		root.add_child(tooltip)
		await _settle()
		_expect(tooltip.size.x <= 400, "Cabinet tooltip must stay compact")
		tooltip.free()
	_expect(paths.size() == controller.cabinets.size(), "Each cabinet needs a distinct portrait asset")
	ui._sidebar_button.button_pressed = true
	await _settle()
	_expect(ui._log.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "Cabinet bar must not overflow the main layout")
	_expect(ui._log.size.y > 150, "Forecast and log must both have usable vertical space")
	await _capture("fincard-cabinet-bar.png")
	# Exercise the real hover path, including Godot's tooltip positioning.
	var badge: CabinetPortrait = ui._cabinets_box.get_child(0)
	Input.warp_mouse(badge.get_global_rect().get_center())
	if DisplayServer.get_name() != "headless":
		root.grab_focus()
		var motion := InputEventMouseMotion.new()
		motion.position = badge.get_global_rect().get_center()
		motion.global_position = motion.position
		root.push_input(motion, true)
		await create_timer(0.8).timeout
		_expect(_visible_tooltip(root), "Hovering a portrait must open its description popup")
		await _capture("fincard-cabinet-hover.png")
	ui.free()
	controller.free()
	await process_frame
	print("CABINET UI TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _find_portraits(node: Node, portraits: Array[CabinetPortrait]) -> void:
	if node is CabinetPortrait:
		portraits.append(node)
	for child in node.get_children():
		_find_portraits(child, portraits)


func _cabinet_group(state: GameState) -> int:
	for i in state.pending_rewards.size():
		if state.pending_rewards[i].get("type") == Reward.Type.CABINET:
			return i
	return -1


func _visible_tooltip(node: Node) -> bool:
	if node is PopupPanel and node.visible:
		return true
	for child in node.get_children():
		if _visible_tooltip(child):
			return true
	return false
