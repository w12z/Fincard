extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var controller := GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	var labels := controller.labels
	var card: CardDef = controller.cards[&"arcadia_recover_bank_holiday"]
	var expected := "• 若 市场信心 < 45：\n    • 市场信心 +10\n  否则：\n    • 市场信心 +4\n• 国内生产总值 -1%"
	_expect(TextFormatter.effects_text(labels, card.effects) == expected, "Bank holiday must visually separate its branches from the unconditional GDP cost")
	var nested := Effect.from_dict({"kind": "branch", "params": {
		"condition": {"indicator": "confidence", "comparator": "gt", "value": 40},
		"then": [{"kind": "branch", "params": {
			"condition": {"indicator": "inflation", "comparator": "lt", "value": 3},
			"then": [{"kind": "gain_budget", "params": {"amount": 1}}, {"kind": "gain_political_capital", "params": {"amount": 1}}],
			"else": [{"kind": "gain_budget", "params": {"amount": 2}}]
		}}],
		"else": [{"kind": "gain_budget", "params": {"amount": 3}}]
	}})
	var text := TextFormatter.effects_text(labels, [nested, card.effects[1]])
	_expect("\n    • 若 通货膨胀 < 3：\n        • 财政预算 +1\n        • 政治行动点 +1\n      否则：\n        • 财政预算 +2\n  否则：\n    • 财政预算 +3\n• 国内生产总值 -1%" in text, "Nested branches and multiple branch effects retain distinct indentation levels")
	var conditional := Effect.from_dict({"kind": "gain_budget", "params": {"amount": 2}, "condition": {"indicator": "confidence", "comparator": "gt", "value": 40}})
	_expect(TextFormatter.effects_text(labels, [conditional, card.effects[1]]).begins_with("• 若 市场信心 > 40：\n    财政预算 +2\n• 国内生产总值"), "A condition on one effect must not appear to apply to the next effect")
	var then_only := Effect.from_dict({"kind": "branch", "params": {"condition": {"indicator": "confidence", "comparator": "gt", "value": 40}, "then": [{"kind": "gain_budget", "params": {"amount": 1}}]}})
	_expect(TextFormatter.effect_text(labels, then_only) == "若 市场信心 > 40：\n  • 财政预算 +1", "A branch without an else still displays its conditional scope")
	_expect(TextFormatter.effects_text(labels, []).is_empty(), "An empty effect list produces no placeholder bullets")
	for definition: CardDef in controller.cards.values():
		var formatted := TextFormatter.effects_text(labels, definition.effects)
		_expect(formatted.split("\n• ").size() == definition.effects.size(), "Every independent card effect gets its own top-level bullet: %s" % definition.id)
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.gui_embed_subwindows = true
	root.add_child(ui)
	ui.setup(controller, &"arcadia")
	ui._dispatch(Command.choose_reward([]))
	controller.simulation.state.hand.assign([card.id])
	controller.simulation.state.budget = 50
	controller.simulation.state.political_capital = 20
	ui._render()
	for frame in 6:
		await process_frame
	var button: CardButton = ui._hand_box.get_child(0)
	var hand_effects := PackedStringArray()
	for label in button.find_children("*", "Label", true, false):
		if label.text.begins_with("• "):
			hand_effects.append(label.text)
			_expect(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "Branch indentation must not be lost to centered text")
	_expect("\n".join(hand_effects) == expected, "Hand and full hover preview share the same effect hierarchy")
	var preview: Control = button._make_custom_tooltip(button.tooltip_text)
	_expect(expected in preview.find_child("Description", true, false).text, "Tooltip retains branch indentation and unconditional effects")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			var popup := PopupPanel.new()
			popup.theme = ui.theme
			root.add_child(popup)
			popup.add_child(preview)
			popup.popup(Rect2i(650, 270, 410, 320))
			for frame in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture=").path_join("fincard-effect-branches.png")) == OK, "Branch formatting screenshot saves")
			popup.remove_child(preview)
			popup.free()
	preview.free()
	ui.free()
	controller.free()
	await process_frame
	print("EFFECT TEXT TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
