class_name ResourceAmount
extends HBoxContainer

const BUDGET := preload("res://assets/icons/budget.svg")
const POLITICAL := preload("res://assets/icons/political.svg")


static func create(resource: StringName, value: String, color: Color = UiTheme.TEXT) -> ResourceAmount:
	var display := ResourceAmount.new()
	display.name = "BudgetAmount" if resource == &"budget" else "PoliticalAmount"
	display.alignment = BoxContainer.ALIGNMENT_CENTER
	display.add_theme_constant_override("separation", 4)
	display.tooltip_text = "预算" if resource == &"budget" else "政治行动点"
	display.set_meta("resource", resource)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = BUDGET if resource == &"budget" else POLITICAL
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(icon)
	var amount := Label.new()
	amount.name = "Amount"
	amount.text = value
	amount.add_theme_color_override("font_color", color)
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.add_child(amount)
	return display
