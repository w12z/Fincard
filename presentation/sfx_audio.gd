class_name SfxAudio
extends Node
## One persistent, bounded sound pool per game window; no audio in simulation code.

signal settings_changed
signal sound_played(id: StringName)

const SOUNDS := {
	&"ui_click": "res://assets/audio/sfx/ui_click.wav",
	&"card_play": "res://assets/audio/sfx/card_play.wav",
	&"effect_arrive": "res://assets/audio/sfx/effect_arrive.wav",
	&"turn_settle": "res://assets/audio/sfx/turn_settle.wav",
	&"reward_gain": "res://assets/audio/sfx/reward_gain.wav",
	&"event_alert": "res://assets/audio/sfx/event_alert.wav",
	&"victory": "res://assets/audio/sfx/victory.wav",
	&"defeat": "res://assets/audio/sfx/defeat.wav",
}
const COOLDOWN_MS := {&"ui_click": 60, &"card_play": 65, &"effect_arrive": 280,
	&"turn_settle": 200, &"reward_gain": 140, &"event_alert": 450,
	&"victory": 1200, &"defeat": 1200}
const CHANNELS := 6
const SETTINGS_PATH := "user://audio.cfg"
const SERVICE_META := &"_fincard_sfx_service"

var volume := 0.8
var muted := false
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _last_played := {}
var _semantic_frame := -1


static func ensure(context: Node) -> SfxAudio:
	if not is_instance_valid(context) or not context.is_inside_tree():
		return null
	var root := context.get_tree().root
	var audio := root.get_node_or_null("FincardSfx") as SfxAudio
	if audio == null:
		# Calls from a scene's _ready() happen while the root may be locked.
		# Cache the pending instance too, so controls() cannot create a second one
		# in the interval before the deferred attachment runs.
		var pending = root.get_meta(SERVICE_META) if root.has_meta(SERVICE_META) else null
		if pending is WeakRef:
			audio = pending.get_ref() as SfxAudio
			if is_instance_valid(audio) and not audio.is_queued_for_deletion():
				return audio
		audio = SfxAudio.new()
		audio.name = "FincardSfx"
		root.set_meta(SERVICE_META, weakref(audio))
		audio._attach.call_deferred(weakref(root))
	return audio


func _attach(root_ref: WeakRef) -> void:
	var root := root_ref.get_ref() as Node
	if not is_instance_valid(root) or not root.is_inside_tree() or root.is_queued_for_deletion():
		queue_free()
		return
	root.add_child(self)


static func play(context: Node, id: StringName) -> void:
	var audio := ensure(context)
	if audio != null:
		audio.play_sound(id)


static func play_events(context: Node, events: Array) -> void:
	# Only the most meaningful notification in one resolved batch is played.
	var kinds := {}
	var manual_card := false
	for event: Event in events:
		kinds[event.kind] = true
		if event.kind == Event.Kind.CARD_PLAYED and not event.params.get("automatic", false):
			manual_card = true
	if kinds.has(Event.Kind.RUN_LOST):
		play(context, &"defeat")
	elif kinds.has(Event.Kind.RUN_WON):
		play(context, &"victory")
	elif kinds.has(Event.Kind.EVENT_TRIGGERED):
		play(context, &"event_alert")
	elif kinds.has(Event.Kind.CARD_GAINED) or kinds.has(Event.Kind.CABINET_APPOINTED) or kinds.has(Event.Kind.AID_GAINED):
		play(context, &"reward_gain")
	elif manual_card:
		play(context, &"card_play")
	elif kinds.has(Event.Kind.AID_USED):
		play(context, &"ui_click")


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		volume = clampf(float(config.get_value("sound", "volume", 0.8)), 0.0, 1.0)
		muted = bool(config.get_value("sound", "muted", false))
	for id in SOUNDS:
		_streams[id] = load(SOUNDS[id]) as AudioStream
	for index in CHANNELS:
		var player := AudioStreamPlayer.new()
		player.volume_db = linear_to_db(maxf(volume, 0.0001))
		add_child(player)
		_players.append(player)
	get_tree().node_added.connect(_watch_button)
	_watch_subtree(get_tree().root)
	# Controls may have subscribed before the deferred node read saved settings.
	settings_changed.emit()


func _watch_subtree(node: Node) -> void:
	_watch_button(node)
	for child in node.get_children():
		_watch_subtree(child)


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null:
		if tree.node_added.is_connected(_watch_button):
			tree.node_added.disconnect(_watch_button)
		var pending = tree.root.get_meta(SERVICE_META) if tree.root.has_meta(SERVICE_META) else null
		if pending is WeakRef and pending.get_ref() == self:
			tree.root.remove_meta(SERVICE_META)
	for player in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_streams.clear()


func _watch_button(node: Node) -> void:
	if not node is BaseButton or node is CardButton or node.has_meta("sfx_connected"):
		return
	# Hand/reward cards get their semantic sound only after a successful action.
	node.set_meta("sfx_connected", true)
	node.pressed.connect(func() -> void:
		if is_instance_valid(node) and not node.disabled:
			_click_after_action.call_deferred(Engine.get_process_frames())
	)


func _click_after_action(frame: int) -> void:
	if frame != _semantic_frame:
		play_sound(&"ui_click", false)


func play_sound(id: StringName, semantic: bool = true) -> bool:
	if not _streams.has(id) or _streams[id] == null:
		return false
	if semantic:
		_semantic_frame = Engine.get_process_frames()
	if muted or volume <= 0.0:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -100000)) < int(COOLDOWN_MS.get(id, 100)):
		return false
	var free: AudioStreamPlayer
	for player in _players:
		if not player.playing:
			free = player
			break
	# Drop tiny notifications instead of accumulating a noisy playback backlog.
	if free == null:
		if id not in [&"victory", &"defeat", &"event_alert"]:
			return false
		free = _players[0]
	if id in [&"victory", &"defeat"]:
		for player in _players:
			player.stop()
	free.stream = _streams[id]
	free.volume_db = linear_to_db(maxf(volume, 0.0001))
	free.play()
	_last_played[id] = now
	sound_played.emit(id)
	return true


func set_muted(value: bool, persist: bool = true) -> void:
	muted = value
	_update_settings(persist)


func set_volume(value: float, persist: bool = true) -> void:
	volume = clampf(value, 0.0, 1.0)
	_update_settings(persist)


func _update_settings(persist: bool = true) -> void:
	for player in _players:
		player.volume_db = linear_to_db(maxf(volume, 0.0001))
		if muted or volume <= 0.0:
			player.stop()
	if persist:
		var config := ConfigFile.new()
		config.set_value("sound", "volume", volume)
		config.set_value("sound", "muted", muted)
		config.save(SETTINGS_PATH)
	settings_changed.emit()


static func controls(context: Node) -> HBoxContainer:
	var audio := ensure(context)
	var box := HBoxContainer.new()
	box.name = "SoundControls"
	box.add_theme_constant_override("separation", 6)
	var mute := Button.new()
	mute.toggle_mode = true
	mute.tooltip_text = "开关音效；不影响游戏进度"
	box.add_child(mute)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 76
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.tooltip_text = "音效音量"
	box.add_child(slider)
	var refresh := func() -> void:
		mute.text = "音效：关" if audio.muted else "音效：开"
		mute.set_pressed_no_signal(audio.muted)
		slider.set_value_no_signal(audio.volume * 100)
	audio.settings_changed.connect(refresh)
	box.tree_exiting.connect(func() -> void:
		if is_instance_valid(audio) and audio.settings_changed.is_connected(refresh):
			audio.settings_changed.disconnect(refresh)
	)
	mute.toggled.connect(audio.set_muted)
	slider.value_changed.connect(func(value: float) -> void: audio.set_volume(value / 100))
	refresh.call()
	return box
