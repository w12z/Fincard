extends Control

var controller: GameController
var _screen: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	_add_background()
	controller = GameController.new()
	add_child(controller)
	_show_menu()


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
	menu.start_requested.connect(_on_start_requested)


func _on_start_requested(scenario_id: StringName) -> void:
	var ui := GameUI.new()
	_swap(ui)
	ui.exit_requested.connect(_show_menu)
	ui.setup(controller, scenario_id)


func _swap(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
