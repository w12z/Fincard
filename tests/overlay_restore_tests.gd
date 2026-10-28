extends SceneTree

var failures := 0
var controller: GameController
var ui: GameUI


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare() -> void:
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	while ui._pile_motion_active:
		await process_frame
	for frame in 6:
		await process_frame


func _check_restore(description: String) -> void:
	ui._render()
	ui._render()
	_expect(ui._overlay_root.visible and ui._overlay_box.get_child_count() > 0, "Fixture has an active panel: " + description)
	var signature := ui._overlay_signature
	var first_child := ui._overlay_box.get_child(0).get_instance_id()
	ui._overlay_root.hide()
	ui._render()
	_expect(ui._overlay_root.visible, "Cached panel visibility is restored: " + description)
	_expect(ui._overlay_signature == signature and ui._overlay_box.get_child(0).get_instance_id() == first_child, "Restoration reuses cached content without rebuilding: " + description)


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0.0
	ui = GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	await _prepare()
	var sim := controller.simulation
	sim._fire_event(&"example_event")
	_check_restore("event choice")
	await _prepare()
	sim.state.turn = 4
	sim._offer_turn_reward()
	_check_restore("fourth-turn reward")
	await _prepare()
	sim.state.flags["pending_review"] = true
	_check_restore("start-turn review")
	await _prepare()
	sim.state.flags["pending_retain"] = true
	_check_restore("retained card")
	await _prepare()
	sim.state.flags["pending_discard_draw"] = [{"draw_count": 2}]
	_check_restore("discard/draw choice")
	await _prepare()
	sim.state.run_status = GameState.RunStatus.WON
	_check_restore("result")
	var audio := SfxAudio.ensure(ui)
	ui.free()
	controller.free()
	audio.free()
	await create_timer(0.15).timeout
	print("OVERLAY RESTORE TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
