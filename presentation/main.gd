extends Control

var controller: GameController
var _screen: Control
var _sound_controls: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	_add_background()
	SfxAudio.ensure(self)
	controller = GameController.new()
	add_child(controller)
	_show_menu()
	_sound_controls = SfxAudio.controls(self)
	add_child(_sound_controls)
	_sound_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_sound_controls.offset_left = -230
	_sound_controls.offset_right = -20
	_sound_controls.offset_top = 16
	_sound_controls.offset_bottom = 48


func _add_background() -> void:
	var background := TextureRect.new()
	background.texture = UiTheme.gradient_background()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)


func _show_menu() -> void:
	var menu := ScenarioMenu.new()
	_swap(menu)
	menu.setup(controller)
	menu.country_selected.connect(_show_country_profile)


func _show_country_profile(scenario_id: StringName) -> void:
	var profile := CountryProfile.new()
	_swap(profile)
	profile.start_requested.connect(_on_start_requested)
	profile.back_requested.connect(_show_menu)
	profile.setup(controller, scenario_id)


func _on_start_requested(scenario_id: StringName) -> void:
	var ui := GameUI.new()
	_swap(ui)
	ui.exit_requested.connect(_show_menu)
	ui.setup(controller, scenario_id)


func _swap(screen: Control) -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
	_screen = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	if is_instance_valid(_sound_controls):
		_sound_controls.visible = not screen is GameUI
		move_child(_sound_controls, get_child_count() - 1)
