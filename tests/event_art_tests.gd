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


func _frames() -> void:
	for frame in 8:
		await process_frame


func _run() -> void:
	var controller := GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	_expect(controller.events.size() == 26, "All twenty-six events must have illustrations")
	for id in controller.events:
		var picture := ArtAssets.event_picture(id)
		_expect(picture != null and picture.texture != null, "Event picture loads: %s" % id)
		if picture != null:
			_expect(picture.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Illustrations do not intercept event choices")
			picture.free()
	_expect(ArtAssets.texture("res://assets/cards/reform_permanent_coordination.png") != null, "New rare political-income reform has its own illustration")
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	for id in controller.events:
		ui.setup(controller, &"arcadia")
		ui._dispatch(Command.choose_reward([]))
		while ui._pile_motion_active:
			await process_frame
		controller.simulation._fire_event(id)
		ui._render()
		await _frames()
		var image := ui._overlay_box.get_node_or_null("EventIllustration") as TextureRect
		_expect(image != null and image.is_visible_in_tree() and image.size.y >= 150, "Each event displays its horizontal banner: %s" % id)
		_expect(ui._overlay_root.visible, "Illustrated event still has a visible modal")
		var buttons := 0
		for child in ui._overlay_box.get_children():
			if child is Button:
				buttons += 1
		var event: EconomyEventDef = controller.events[id]
		_expect(buttons == maxi(1, event.choices.size()), "Art does not remove or duplicate choices: %s" % id)
		if not capture_directory.is_empty() and DisplayServer.get_name() != "headless" \
			and id in [&"arcadia_ev_black_thursday", &"arcadia_ev_bank_panic", &"arcadia_ev_recovery_direction"]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture_directory.path_join("fincard-art-%s.png" % id))
	var audio := SfxAudio.ensure(ui)
	ui.free()
	controller.free()
	audio.free()
	await create_timer(0.15).timeout
	print("EVENT ART TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
