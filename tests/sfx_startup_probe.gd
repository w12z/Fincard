extends "res://presentation/main.gd"
## Run as a scene, not a deferred SceneTree test, to exercise real startup locks.

var _failures := 0
var _pending_audio: SfxAudio


func _ready() -> void:
	super._ready()
	_pending_audio = SfxAudio.ensure(self)
	_expect(SfxAudio.ensure(self) == _pending_audio, "Startup reuses its pending audio instance")
	_verify.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)


func _verify() -> void:
	var audio := SfxAudio.ensure(self)
	_expect(audio == _pending_audio and audio.is_inside_tree(), "Pending audio must attach before use")
	var count := 0
	for child in get_tree().root.get_children():
		if child is SfxAudio:
			count += 1
	_expect(count == 1 and audio._players.size() == 6, "Normal startup has exactly one audio service and six voices")
	_expect(is_equal_approx(_sound_controls.get_child(1).value, audio.volume * 100), "Menu controls show saved volume after deferred initialization")
	for id in [&"example_country", &"arcadia"]:
		_show_country_profile(id)
		_expect(_screen is CountryProfile, "Country profile opens after real startup")
		_on_start_requested(id)
		_expect(_screen is GameUI, "Gameplay opens after real startup")
		_screen._dispatch(Command.choose_reward([]))
		for frame in 6:
			await get_tree().process_frame
		_expect(SfxAudio.ensure(self) == audio, "Switching scenes does not duplicate audio")
	_show_menu()
	var tree := get_tree()
	# Release the audio service after menu controls have disconnected their signals.
	_screen.free()
	_screen = null
	_sound_controls.free()
	_sound_controls = null
	audio.queue_free()
	await tree.create_timer(0.15).timeout
	print("REAL SCENE STARTUP TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	tree.quit(0 if _failures == 0 else 1)
