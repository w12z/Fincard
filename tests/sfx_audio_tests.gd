extends SceneTree

var failures := 0
var counts := {}


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _frames(count: int = 6) -> void:
	for frame in count:
		await process_frame


func _run() -> void:
	var main = load("res://presentation/main.tscn").instantiate()
	root.add_child(main)
	var audio := SfxAudio.ensure(main)
	_expect(SfxAudio.ensure(main) == audio, "Repeated ensure calls reuse the pending service before attachment")
	await _frames()
	_expect(root.get_node_or_null("FincardSfx") == audio, "Deferred audio service attaches successfully")
	var old_muted := audio.muted
	var old_volume := audio.volume
	audio.set_muted(false, false)
	audio.set_volume(0.8, false)
	audio.sound_played.connect(func(id: StringName) -> void: counts[id] = int(counts.get(id, 0)) + 1)
	_expect(SfxAudio.ensure(main) == audio and audio._players.size() == 6, "Use one persistent bounded audio pool")
	for id in SfxAudio.SOUNDS:
		_expect(audio._streams[id] != null, "Every approved sound must load: %s" % id)
	_expect(is_equal_approx(audio._streams[&"card_play"].get_length(), 0.26), "Use revised card sound, not the rejected tail version")
	_expect(is_equal_approx(audio._streams[&"turn_settle"].get_length(), 0.27), "Use revised non-melodic settlement sound")
	_expect(main._sound_controls.visible, "Menu exposes sound controls")
	main.controller.rules["random_event_chance"] = 0.0
	main._on_start_requested(&"example_country")
	var ui: GameUI = main._screen
	_expect(not main._sound_controls.visible and ui._header.get_node_or_null("SoundControls") != null, "Gameplay exposes its own compact sound controls")
	ui._dispatch(Command.choose_reward([]))
	while ui._pile_motion_active:
		await process_frame
	counts.clear()
	ui._goal_button.pressed.emit()
	await _frames()
	_expect(int(counts.get(&"ui_click", 0)) == 1, "Ordinary UI buttons play one light confirmation click")
	var sim: Simulation = main.controller.simulation
	sim.state.budget = 100
	sim.state.political_capital = 20
	sim.state.hand.assign([&"starter_small_business"])
	ui._render()
	await _frames()
	counts.clear()
	ui._hand_box.get_child(0).pressed.emit()
	_expect(int(counts.get(&"card_play", 0)) == 1, "Successful hand play sounds exactly once")
	ui._render()
	_expect(int(counts.get(&"card_play", 0)) == 1, "Redraws do not replay the sound")
	await create_timer(1.15).timeout
	_expect(not counts.has(&"ui_click"), "Successful card plays do not also stack a generic button sound")
	_expect(int(counts.get(&"effect_arrive", 0)) == 1, "An arriving modifier plays effect feedback")
	counts.clear()
	ui._dispatch(Command.play_card(&"missing_card"))
	_expect(counts.is_empty(), "Rejected actions do not play success sounds")
	ui._dispatch(Command.end_turn())
	_expect(not counts.has(&"turn_settle"), "Settlement does not sound complete before its animation")
	while ui._settlement_active or ui._pile_motion_active:
		await process_frame
	_expect(int(counts.get(&"turn_settle", 0)) == 1, "Settlement sound fires once at numeric completion")
	await _frames()
	counts.clear()
	main._on_start_requested(&"example_country")
	ui = main._screen
	var group: Dictionary = sim.state.pending_rewards[0]
	ui._claim_reward(0, 0, str(group["token"]))
	_expect(int(counts.get(&"reward_gain", 0)) == 1, "Actually gaining a reward plays the reward sound")
	await create_timer(0.16).timeout
	counts.clear()
	ui._claim_reward(0, -1, str(sim.state.pending_rewards[0]["token"]))
	_expect(not counts.has(&"reward_gain"), "Skipping a reward does not play a gain sound")
	counts.clear()
	SfxAudio.play_events(main, [Event.new(Event.Kind.EVENT_TRIGGERED)])
	_expect(int(counts.get(&"event_alert", 0)) == 1, "Event presentation has its own notification")
	counts.clear()
	for index in 12:
		audio.play_sound(&"effect_arrive")
	_expect(int(counts.get(&"effect_arrive", 0)) <= 1, "Concurrent number landings are rate-limited")
	counts.clear()
	SfxAudio.play_events(main, [Event.new(Event.Kind.CARD_GAINED), Event.new(Event.Kind.RUN_WON)])
	_expect(int(counts.get(&"victory", 0)) == 1 and not counts.has(&"reward_gain"), "Victory takes precedence over minor notifications")
	SfxAudio.play_events(main, [Event.new(Event.Kind.RUN_LOST)])
	_expect(int(counts.get(&"defeat", 0)) == 1, "Defeat uses the approved defeat sound")
	audio.set_muted(true, false)
	counts.clear()
	audio.play_sound(&"ui_click")
	_expect(counts.is_empty(), "Muted sound cannot play")
	for player in audio._players:
		_expect(not player.playing, "Muting immediately stops active audio")
	audio.set_muted(false, false)
	audio.set_volume(0.0, false)
	_expect(not audio.play_sound(&"card_play"), "Zero volume is silent")
	# Restore in-memory preferences; this check never writes the user's settings.
	audio.set_volume(old_volume, false)
	audio.set_muted(old_muted, false)
	main.free()
	await _frames()
	audio.free()
	# Allow the audio mix thread to release stopped playback resources.
	await create_timer(0.12).timeout
	print("SFX AUDIO TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
