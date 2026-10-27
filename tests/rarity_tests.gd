extends SceneTree

var failures := 0
var controller: GameController


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _prepare() -> Simulation:
	var sim := controller.simulation
	sim.rng = Rng.new(7)
	sim.start_run(&"example_country")
	sim.apply_command(Command.choose_reward([]))
	return sim


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_distribution()
	_test_cabinet_rarities()
	_test_rewards()
	_test_modifiers()
	_test_special_grants()
	await _test_ui()
	controller.free()
	print("RARITY TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_distribution() -> void:
	var sim := _prepare()
	var candidates: Array[StringName] = []
	# An intentionally uneven population must not skew rarity probabilities.
	for i in 12:
		var card := CardDef.from_dict({"id": "test_common_%d" % i})
		sim.card_db[card.id] = card
		candidates.append(card.id)
	candidates.append(&"reform_research_network")
	candidates.append(&"reform_emergency_authority")
	candidates.append(&"special_national_strategy")
	var counts := {&"common": 0, &"rare": 0, &"legendary": 0, &"special": 0}
	for i in 26000:
		var id := sim._pick_reward_card(candidates)
		counts[sim.card_db[id].rarity] += 1
	_expect(absf(counts[&"common"] / 26000.0 - 20.0 / 26) < 0.015, "Common tier should follow 20/26, independent of its card count")
	_expect(absf(counts[&"rare"] / 26000.0 - 5.0 / 26) < 0.015, "Rare tier should follow 5/26")
	_expect(absf(counts[&"legendary"] / 26000.0 - 1.0 / 26) < 0.008, "Legendary tier should follow 1/26")
	_expect(counts[&"special"] == 0, "Special tier must never enter weighted rolls")
	for i in 12:
		sim.card_db.erase(StringName("test_common_%d" % i))
	_expect(sim._pick_reward_card([&"special_national_strategy"]) == &"", "Special-only pool produces no annual card")
	_expect(sim._pick_reward_card([&"reform_emergency_authority"]) == &"reform_emergency_authority", "Unavailable tiers are excluded instead of yielding empty slots")
	var candidates_copy := candidates.duplicate()
	var first := Rng.new(123)
	var second := Rng.new(123)
	sim.rng = first
	var roll1 := sim._pick_reward_card([&"example_card", &"reform_research_network", &"reform_emergency_authority"])
	sim.rng = second
	var roll2 := sim._pick_reward_card([&"example_card", &"reform_research_network", &"reform_emergency_authority"])
	_expect(roll1 == roll2 and candidates == candidates_copy, "Reward rolls are seeded and do not mutate candidate pools")


func _test_cabinet_rarities() -> void:
	var sim := _prepare()
	var candidates: Array[StringName] = []
	for rarity in CardDef.RARITIES:
		for i in (12 if rarity == &"common" else 1):
			var id := StringName("test_cab_%s_%d" % [rarity, i])
			sim.cabinet_db[id] = CabinetDef.from_dict({"id": id, "rarity": String(rarity)})
			candidates.append(id)
	var counts := {&"common": 0, &"rare": 0, &"legendary": 0, &"special": 0}
	for i in 26000:
		counts[sim.cabinet_db[sim._pick_rarity_reward(candidates, sim.cabinet_db)].rarity] += 1
	_expect(absf(counts[&"common"] / 26000.0 - 20.0 / 26) < 0.015 and absf(counts[&"rare"] / 26000.0 - 5.0 / 26) < 0.015 and absf(counts[&"legendary"] / 26000.0 - 1.0 / 26) < 0.008, "Cabinet tier odds are 20:5:1 regardless of population")
	_expect(counts[&"special"] == 0, "Special cabinets never enter annual weighted rolls")
	sim.state.modifiers.append(Modifier.new(&"common", Modifier.Op.OVERRIDE, 0, -1, &"", &"reward"))
	sim.state.modifiers.append(Modifier.new(&"rare", Modifier.Op.OVERRIDE, 0, -1, &"", &"reward"))
	for i in 20:
		_expect(sim.cabinet_db[sim._pick_rarity_reward(candidates, sim.cabinet_db)].rarity == &"legendary", "Shared reward modifiers immediately affect cabinet rolls")
	sim.state.modifiers.append(Modifier.new(&"legendary", Modifier.Op.OVERRIDE, 0, -1, &"", &"reward"))
	_expect(sim._pick_rarity_reward(candidates, sim.cabinet_db) == &"", "All-zero cabinet weights safely return no candidate")
	for id in candidates:
		sim.cabinet_db.erase(id)
	for scenario in [&"example_country", &"arcadia"]:
		sim.start_run(scenario)
		for i in 100:
			for group in sim._build_year_end_rewards():
				if group["type"] != Reward.Type.CABINET:
					continue
				_expect(group["options"].size() == (1 if scenario == &"example_country" else 2), "Offer two cabinet candidates, or the remaining available count")
				var seen := {}
				for reward: Reward in group["options"]:
					_expect(not seen.has(reward.id) and sim._reward_available(Reward.Type.CABINET, reward.id), "Cabinet candidates are unique, available and country-appropriate")
					seen[reward.id] = true
	sim._appoint_cabinet(&"arcadia_cab_treasury")
	_expect(not sim._reward_available(Reward.Type.CABINET, &"arcadia_cab_treasury"), "Appointed cabinets do not reappear")
	var special := CabinetDef.from_dict({"id": "test_special_cab", "rarity": "special"})
	sim.cabinet_db[special.id] = special
	_expect(not sim._reward_available(Reward.Type.CABINET, special.id), "Special cabinets cannot bypass annual rarity restrictions")
	sim._appoint_cabinet(special.id)
	_expect(sim.state.cabinets.has(special), "Special cabinets remain available through explicit appointments")
	sim.state.cabinets.erase(special)
	sim.cabinet_db.erase(special.id)


func _test_rewards() -> void:
	for scenario in [&"example_country", &"arcadia"]:
		var sim := controller.simulation
		sim.start_run(scenario)
		for i in 100:
			var offered_laws := {}
			for group in sim._build_year_end_rewards():
				var offered := {}
				for reward: Reward in group["options"]:
					if reward.type != Reward.Type.CARD:
						continue
					var card: CardDef = sim.card_db[reward.id]
					_expect(card.rarity != &"special" and sim._member_allowed("cards", card.id), "Annual cards obey rarity and country restrictions")
					_expect(not offered.has(card.id), "A reward group cannot duplicate cards")
					offered[card.id] = true
					if card.once_per_run:
						_expect(not offered_laws.has(card.id), "A law cannot appear in both annual groups")
						offered_laws[card.id] = true
		_expect(not sim._reward_available(Reward.Type.CARD, &"special_national_strategy"), "Special cards are not valid annual rewards")
		_expect(sim._grant_reward(Reward.new(Reward.Type.CARD, &"special_national_strategy", "")).is_empty(), "Annual grant cannot bypass special-card restriction")
	var sim := _prepare()
	sim.state.modifiers.append(Modifier.new(&"rare", Modifier.Op.OVERRIDE, 0, -1, &"", &"reward"))
	sim.state.modifiers.append(Modifier.new(&"legendary", Modifier.Op.OVERRIDE, 0, -1, &"", &"reward"))
	for i in 30:
		_expect(sim.card_db[sim._pick_reward_card([&"example_card", &"reform_research_network", &"reform_executive_mandate"])].rarity == &"common", "Zero-weight tiers are never selected")
	sim.state.modifiers.append(Modifier.new(&"common", Modifier.Op.OVERRIDE, 0, -1, &"", &"reward"))
	_expect(sim._pick_reward_card([&"example_card"]) == &"", "All-zero weights safely produce no card")
	var groups: Array[Dictionary] = []
	sim._add_reward_group(groups, Reward.Type.CARD, [&"example_card", &"reform_executive_mandate"], 3)
	_expect(groups.is_empty(), "All-zero weights omit empty card reward groups")
	sim.state.modifiers.clear()
	sim._add_reward_group(groups, Reward.Type.CARD, [&"special_national_strategy"], 3)
	_expect(groups.is_empty(), "Special-only annual pools omit card groups")


func _test_modifiers() -> void:
	var sim := _prepare()
	_expect(sim.rarity_weight(&"common") == 20 and sim.rarity_weight(&"rare") == 5 and sim.rarity_weight(&"legendary") == 1, "Initial weights are exactly 20:5:1")
	sim._appoint_cabinet(&"arcadia_cab_braintrust")
	_expect(sim.rarity_weight(&"rare") == 10 and sim.rarity_weight(&"legendary") == 1, "Brain trust adds rare weight without changing other weights")
	sim.state.hand.assign([&"reform_research_network"])
	sim.state.political_capital = 100
	sim.apply_command(Command.play_card(&"reform_research_network"))
	_expect(sim.rarity_weight(&"rare") == 15 and sim.rarity_weight(&"legendary") == 2, "Reform stacks with cabinet weights")
	var found := false
	for entry in ModifierDisplay.entries(sim, controller.labels):
		if entry["key"] == "reward:rare":
			found = entry["counter"] == "+10"
	_expect(found, "Reward modifiers merge in the unified modifier bar")
	for i in 8:
		sim._advance_modifiers()
	_expect(sim.rarity_weight(&"rare") == 15, "Permanent weight boosts survive per-turn expiry")
	sim = _prepare()
	_expect(sim.rarity_weight(&"rare") == 5 and sim.rarity_weight(&"legendary") == 1, "Restart clears reward weight bonuses")


func _test_special_grants() -> void:
	var sim := _prepare()
	sim._appoint_cabinet(&"arcadia_cab_braintrust")
	_expect(not sim.state.deck.has(&"special_national_strategy"), "One legendary cabinet does not grant the blueprint")
	sim._appoint_cabinet(&"arcadia_cab_labor")
	_expect(sim.state.deck.count(&"special_national_strategy") == 1, "Two distinct legendary cabinets grant the blueprint")
	sim._appoint_cabinet(&"arcadia_cab_labor")
	_expect(sim.state.deck.count(&"special_national_strategy") == 1, "A repeated appointment cannot duplicate the blueprint")
	var effect := Effect.from_dict({"kind": "gain_card", "params": {"card": "special_national_strategy"}})
	_expect(sim.resolver.resolve(effect, sim.state, sim.rng).is_empty(), "Unique special cards cannot be duplicated")
	sim.state.deck.erase(&"special_national_strategy")
	var event := EconomyEventDef.from_dict({"id": "test_special_grant", "choices": [{"label": "领取", "effects": [{"kind": "gain_card", "params": {"card": "special_national_strategy"}}]}]})
	sim.event_db[event.id] = event
	sim._fire_event(event.id)
	sim.apply_command(Command.resolve_event(0))
	_expect(sim.state.deck.has(&"special_national_strategy"), "Event effects can grant special cards outside annual pools")
	sim.event_db.erase(event.id)
	sim.state.deck.erase(&"special_national_strategy")
	# Combo/conditional effects use the same grant path, without a second lottery.
	var branch := Effect.from_dict({"kind": "branch", "params": {"condition": {"indicator": "gdp", "comparator": "ge", "value": 100}, "then": [{"kind": "gain_card", "params": {"card": "special_national_strategy"}}]}})
	sim.resolver.resolve(branch, sim.state, sim.rng)
	_expect(sim.state.deck.count(&"special_national_strategy") == 1, "Conditional/combo effects use the same explicit grant mechanism")
	sim.state.hand.assign([&"special_national_strategy"])
	sim.state.deck.erase(&"special_national_strategy")
	sim.state.political_capital = 100
	sim.apply_command(Command.play_card(&"special_national_strategy"))
	_expect(sim.resolver.resolve(effect, sim.state, sim.rng).is_empty(), "Enacted special laws cannot be granted again")


func _check_card_colors(control: Control, card: CardDef) -> void:
	for label in control.find_children("*", "Label", true, false):
		var expected := UiTheme.TEXT
		if label.name == "CardName":
			expected = UiTheme.card_type_color(card.card_type)
		_expect(label.name != "Rarity", "Card faces must not contain a text rarity label")
		_expect(label.get_theme_color("font_color") == expected, "Only card names use type colors; other card text stays black: %s" % label.text)


func _test_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	var text := ""
	for child in ui._overlay_box.get_children():
		if child is Label or child is CheckBox:
			text += child.text
	_expect("普通 20" in text and "稀有 5" in text and "传奇 1" in text, "Annual modal shows effective rarity weights")
	ui._reward_group_index = 0
	ui._overlay_signature = GameUI.UNSET_SIGNATURE
	ui._render_overlay()
	for choice in ui._overlay_box.get_child(1).get_children():
		if choice is CardButton:
			_check_card_colors(choice, choice.preview_card)
			_expect(choice._styles["normal"].border_color == UiTheme.rarity_color(choice.preview_card.rarity), "Reward cards use rarity-colored edges")
	ui._dispatch(Command.choose_reward([]))
	controller.simulation.state.hand.assign([&"special_national_strategy", &"reform_emergency_authority", &"reform_research_network", &"example_card"])
	ui._render()
	for i in 4:
		var badge: Button = ui._hand_box.get_child(i)
		var card: CardDef = controller.cards[controller.simulation.state.hand[i]]
		_expect(badge._styles["normal"].border_color == UiTheme.rarity_color(card.rarity), "Hand border displays the card rarity")
		_expect(badge.find_child("Illustration", true, false) != null, "Hand cards have an illustration area")
		_check_card_colors(badge, card)
		var preview: Control = badge._make_custom_tooltip(badge.tooltip_text)
		_check_card_colors(preview, card)
		_expect(preview.get_theme_stylebox("panel").border_color == UiTheme.rarity_color(card.rarity), "Hover previews use the same rarity border")
		preview.free()
	ui._played_table.render(controller.simulation.state.hand, controller.cards, controller.labels)
	for button in ui._played_table._cards:
		_check_card_colors(button, controller.cards[button.get_meta("card_id")])
	var expected_colors := [Color("737373"), Color("2563b8"), Color("b58112"), Color("d9363e")]
	for i in CardDef.RARITIES.size():
		_expect(UiTheme.rarity_color(CardDef.RARITIES[i]) == expected_colors[i], "Rarity palette must be gray, blue, gold and red")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			for frame in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture=").path_join("fincard-rarity-colors.png")) == OK, "Rarity color screenshot saves")
	ui.free()
	await process_frame
