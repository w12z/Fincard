class_name CardPreview
extends RefCounted


static func name_label(card: CardDef) -> Label:
	var label := Label.new()
	label.name = "CardName"
	label.text = card.display_name
	label.add_theme_color_override("font_color", UiTheme.card_type_color(card.card_type))
	return label


static func rarity_label(card: CardDef, labels: Dictionary) -> Label:
	var label := Label.new()
	label.name = "Rarity"
	label.text = "［%s］" % TextFormatter.rarity_name(labels, card.rarity)
	label.add_theme_color_override("font_color", UiTheme.rarity_color(card.rarity))
	return label


static func build(details: String, budget: String, political: String, card: CardDef = null, labels: Dictionary = {}) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme._panel_style(UiTheme.PANEL_BG, UiTheme.PANEL_BORDER, 10, 1, 12))
	var content := VBoxContainer.new()
	panel.add_child(content)
	content.add_theme_constant_override("separation", 8)
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 16)
	costs.add_child(ResourceAmount.create(&"budget", budget))
	costs.add_child(ResourceAmount.create(&"political", political))
	content.add_child(costs)
	if card != null:
		content.add_child(name_label(card))
		content.add_child(rarity_label(card, labels))
		var type_label := Label.new()
		type_label.text = TextFormatter.card_type_name(labels, card.card_type)
		type_label.add_theme_color_override("font_color", UiTheme.TEXT)
		content.add_child(type_label)
	var description := Label.new()
	description.name = "Description"
	description.text = details.substr(details.find("\n") + 1) if card != null and "\n" in details else details
	description.add_theme_color_override("font_color", UiTheme.TEXT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 340
	content.add_child(description)
	return panel


class RewardChoice extends CheckBox:
	var preview_budget := "0"
	var preview_political := "0"
	var is_card := false
	var preview_card: CardDef
	var preview_labels := {}


	func _make_custom_tooltip(for_text: String) -> Object:
		return CardPreview.build(for_text, preview_budget, preview_political, preview_card, preview_labels) if is_card else null
