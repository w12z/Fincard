extends SceneTree

var controller: GameController
var failures: int = 0


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
	sim.state.budget = 100
	sim.state.political_capital = 100
	return sim


func _play(sim: Simulation, id: StringName) -> void:
	sim.state.hand.assign([id])
	_expect(not sim.apply_command(Command.play_card(id)).is_empty(), "Card must be playable: %s" % id)


func _snapshot(state: GameState) -> GameState:
	var copy := GameState.new()
	copy.indicators = state.indicators.duplicate(true)
	copy.modifiers = state.modifiers.duplicate()
	return copy


func _run() -> void:
	controller = GameController.new()
	controller.seed_value = 7
	root.add_child(controller)
	controller.rules["random_event_chance"] = 0
	_test_card_descriptions()
	_test_political_cards()
	_test_funding()
	_test_rebalanced_cards()
	_test_rates()
	_test_investments()
	_test_payments()
	_test_event_budget()
	_test_event_preview_ordering()
	_test_event_preview_isolation()
	_test_relief()
	_test_branches()
	await _test_event_ui()
	_expect(TextFormatter.fmt(0.625) == "0.625" and TextFormatter.fmt(-0.003) == "-0.003", "Small economic effects must not round to zero or lose precision")
	controller.free()
	await process_frame
	print("CARD EFFECT TESTS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_political_cards() -> void:
	var definitions := [
		[&"policy_legislative_liaison", &"common", 3, 1, 3],
		[&"policy_coalition_negotiation", &"rare", 4, 1, 5],
		[&"policy_national_consensus", &"legendary", 6, 2, 8],
	]
	for scenario in controller.scenarios:
		for definition in definitions:
			var sim := controller.simulation
			sim.start_run(scenario)
			sim.apply_command(Command.choose_reward([]))
			var id: StringName = definition[0]
			var card: CardDef = controller.cards[id]
			_expect(card.rarity == definition[1] and card.cost == definition[2] and card.political_cost == definition[3], "Political cards have distinct rarity and explicit upfront costs")
			_expect(sim._reward_available(Reward.Type.CARD, id) and sim.card_reward_pool.has(id), "Both countries can receive political cards through annual rewards")
			sim.state.hand.assign([id])
			sim.state.budget = card.cost - 1
			var political := sim.state.political_capital
			_expect(sim.apply_command(Command.play_card(id)).is_empty() and sim.state.hand.has(id) and sim.state.political_capital == political, "Political card cannot use its reward before paying its budget cost")
			sim.state.budget = 20
			sim.state.political_capital = card.political_cost - 1
			_expect(sim.apply_command(Command.play_card(id)).is_empty() and sim.state.budget == 20, "Political card requires upfront political points, even though it grants more")
			sim.state.political_capital = card.political_cost
			_expect(not sim.apply_command(Command.play_card(id)).is_empty(), "Political card is playable when exact upfront costs are available")
			_expect(sim.state.budget == 20 - card.cost and sim.state.political_capital == definition[4], "Cost is paid first, then the stated political reward is granted")
			_expect(sim.state.discard.has(id) and not sim.state.hand.has(id), "Political cards cycle as normal policies, not one-time laws")
			sim.state.hand.assign([&"reform_executive_mandate"])
			_expect(not sim.apply_command(Command.play_card(&"reform_executive_mandate")).is_empty(), "Gained points are immediately usable for a high-cost reform")
			var forecast := sim.forecast_next_turn()
			sim.apply_command(Command.end_turn())
			_expect(sim.state.political_capital == 3 and forecast.political_capital == 3, "Political card rewards do not change the next turn's reset target")
	var sim := _prepare()
	sim.resolver.resolve(Effect.from_dict({"kind": "grant_status", "params": {"status": "executive_mandate"}}), sim.state, sim.rng)
	sim.state.political_capital = 0
	_play(sim, &"policy_legislative_liaison")
	_expect(sim.state.political_capital == 3, "First-card political discount applies normally to political resource cards")


func _test_card_descriptions() -> void:
	var mechanics := RegEx.new()
	mechanics.compile("[0-9%+×]|永久|每回合|回合内|一次性|预算成本|政治成本|出现权重|抽.{0,3}张")
	for card: CardDef in controller.cards.values():
		_expect(not card.description.strip_edges().is_empty(), "Card must retain its background description: %s" % card.id)
		_expect(mechanics.search(card.description) == null, "Card description must not repeat mechanical rules: %s" % card.id)
		var effects := TextFormatter.effects_text(controller.labels, card.effects)
		_expect(not effects.is_empty() and not "未知效果" in effects, "Card effects must remain independently readable: %s" % card.id)
		_expect(not "月" in effects and not "月" in card.description, "Card wording uses turns consistently: %s" % card.id)
	var synergy := TextFormatter.effects_text(controller.labels, controller.cards[&"reform_policy_synergy"].effects)
	_expect("每回合第三张牌结算后抽 2 张" in synergy, "Synergy effect states its trigger and draw amount")
	var funds := TextFormatter.effects_text(controller.labels, controller.cards[&"reform_earmarked_funds"].effects)
	_expect("每回合首张投资与援助类卡牌预算 -2" in funds, "Investment effect states its exact card category and discount")


func _test_funding() -> void:
	var grants := {&"arcadia_reform_austerity": 3}
	for id in grants:
		var sim := _prepare()
		var control := _snapshot(sim.state)
		_play(sim, id)
		_expect(sim.state.budget == 100 + grants[id], "Funding policy must immediately grant the printed budget: %s" % id)
		_expect(sim.state.indicators == control.indicators and sim.state.modifiers.size() == control.modifiers.size(), "Funding must not create economic indicators or ongoing fiscal effects")
		sim.economy.tick(sim.state, sim.rng)
		_expect(sim.state.budget == 100 + grants[id], "Funding must not repeat at settlement")


func _test_rates() -> void:
	for id in [&"arcadia_policy_bond_yield", &"arcadia_recover_open_market"]:
		var sim := _prepare()
		var control := _snapshot(sim.state)
		_play(sim, id)
		for target in [&"inflation", &"gdp", &"confidence", &"unemployment"]:
			_expect(sim.state.indicators[target] == control.indicators[target], "Monetary policy must not directly change downstream indicator: %s" % target)
		var tighter: bool = id == &"arcadia_policy_bond_yield"
		var adjustment := 1 if tighter else -1
		_expect(is_equal_approx(sim.economy.value(sim.state, &"interest_rate"), 3 + adjustment), "Rate policies change the effective rate by exactly one")
		_expect(sim.state.modifiers.back().remaining_turns == 2, "Rate policies last two turns")
		sim.economy.tick(control, Rng.new(7))
		sim.economy.tick(sim.state, sim.rng)
		_expect((sim.state.indicators[&"inflation"] < control.indicators[&"inflation"]) == tighter, "Rates must affect inflation at settlement")
		_expect((sim.state.indicators[&"gdp"] < control.indicators[&"gdp"]) == tighter, "Rates must affect growth at settlement")
		_expect(sim.state.budget == 100 - controller.cards[id].cost, "Interest rates must not automatically change budget")
		sim._advance_modifiers()
		_expect(is_equal_approx(sim.economy.value(sim.state, &"interest_rate"), 3 + adjustment), "Rate modifier still applies after the first settlement")
		sim._advance_modifiers()
		_expect(is_equal_approx(sim.economy.value(sim.state, &"interest_rate"), 3), "Rate modifier expires after the second settlement")


func _test_rebalanced_cards() -> void:
	var sim := _prepare()
	_play(sim, &"arcadia_reform_tax_wealth")
	_expect(sim.state.budget == 100 and sim.annual_income() == 36, "Wealth tax increases annual income by four without an immediate payout")
	for i in 3:
		sim._advance_modifiers()
		sim.state.budget = 0
		sim._grant_year_resources()
		_expect(sim.state.budget == 36 and sim.annual_income() == 36, "Wealth tax contributes to every future annual payment permanently")
	sim = _prepare()
	var growth := sim.economy.coefficient(sim.state, &"gdp_auto")
	_play(sim, &"arcadia_recover_tariff")
	_expect(sim.state.budget == 100 and sim.state.indicators[&"confidence"] == 52, "Tariff grants two confidence and no budget")
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), growth - 0.1), "Tariff reduces potential growth by 0.1")
	sim._advance_modifiers()
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), growth - 0.1), "Tariff growth penalty includes a second settlement")
	_play(sim, &"arcadia_recover_tariff")
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), growth - 0.2), "Repeated tariffs stack independently")
	sim._advance_modifiers()
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), growth - 0.1), "Earlier tariff expires independently")
	sim._advance_modifiers()
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"gdp_auto"), growth), "Tariff growth penalty expires after two turns")
	sim = _prepare()
	_play(sim, &"arcadia_reform_social_security")
	_expect(is_equal_approx(sim.economy.coefficient(sim.state, &"natural_unemployment"), 6) and sim.economy.value(sim.state, &"confidence") == 62, "Social security gives twelve confidence without changing natural unemployment")
	sim = _prepare()
	sim.state.indicators[&"interest_rate"] = 4
	_play(sim, &"arcadia_recover_gold")
	_expect(sim.state.indicators[&"interest_rate"] == 4 and sim.economy.value(sim.state, &"interest_rate") == 1 and sim.state.indicators[&"confidence"] == 40, "Leaving gold applies a permanent rate modifier and an immediate confidence cost")
	sim = _prepare()
	sim.state.indicators[&"interest_rate"] = 2
	_play(sim, &"arcadia_recover_gold")
	_expect(sim.economy.value(sim.state, &"interest_rate") == 0, "The permanent rate modifier still respects the zero boundary")
	var expected: Array[StringName] = [&"arcadia_relief_dole", &"arcadia_relief_dole", &"arcadia_reform_austerity", &"arcadia_policy_bond_yield", &"arcadia_recover_open_market", &"policy_emergency_cabinet_meeting", &"starter_infrastructure", &"starter_small_business"]
	_expect(controller.scenarios[&"arcadia"].starting_deck == expected, "Arcadia starts with the requested eight cards")
	_expect(controller.cards[&"arcadia_recover_open_market"].display_name == "官方认购国债", "Official bond purchases retains its internal ID with the new display name")


func _test_investments() -> void:
	for id in [&"starter_infrastructure", &"starter_small_business", &"arcadia_relief_works", &"arcadia_recover_trade", &"starter_efficiency"]:
		var sim := _prepare()
		var control := _snapshot(sim.state)
		_play(sim, id)
		for target in [&"gdp", &"unemployment", &"confidence", &"inflation"]:
			if id == &"arcadia_relief_works" and target == &"unemployment":
				_expect(sim.state.indicators[target] == control.indicators[target] - 1, "Public works also directly lowers unemployment by one")
				continue
			_expect(sim.state.indicators[target] == control.indicators[target], "Growth investment must not immediately change %s: %s" % [target, id])
		sim.economy.tick(control, Rng.new(7))
		sim.economy.tick(sim.state, sim.rng)
		_expect(sim.state.indicators[&"gdp"] > control.indicators[&"gdp"], "Investment must increase output through growth")
		_expect(sim.state.indicators[&"unemployment"] < control.indicators[&"unemployment"], "Investment must generate jobs through growth")
		_expect(sim.state.indicators[&"inflation"] > control.indicators[&"inflation"], "Investment demand must affect prices through growth")
		_expect(sim.state.indicators[&"confidence"] > control.indicators[&"confidence"], "Investment must build confidence through growth")
	var sim := _prepare()
	_play(sim, &"starter_infrastructure")
	for remaining in [3, 2, 1, 0]:
		sim.apply_command(Command.end_turn())
		var found := false
		for modifier in sim.state.modifiers:
			if modifier.source == &"基础设施投资":
				found = true
				_expect(modifier.remaining_turns == remaining, "Investment must count down once per settlement")
		_expect(found == (remaining > 0), "Investment must expire after exactly four settlements")


func _test_payments() -> void:
	var sim := _prepare()
	sim.state.budget = 3
	sim.state.hand.assign([&"starter_infrastructure"])
	var before := sim.state.indicators.duplicate()
	_expect(sim.apply_command(Command.play_card(&"starter_infrastructure")).is_empty(), "A project cannot spend more budget than available")
	_expect(sim.state.budget == 3 and sim.state.indicators == before and sim.state.cards_played_this_turn == 0, "Rejected spending must not partially mutate state")
	sim.state.budget = 4
	sim.apply_command(Command.play_card(&"starter_infrastructure"))
	_expect(sim.state.budget == 0, "A funded project must deduct its budget cost exactly once")
	sim.apply_command(Command.end_turn())
	_expect(sim.state.budget == 0, "An ongoing project must not bill its cost again at settlement")
	for id in [&"arcadia_aid_gold", &"arcadia_aid_foreign_loan"]:
		sim = _prepare()
		sim._gain_aid(id)
		sim.apply_command(Command.use_aid(id))
		_expect(sim.state.budget == 100 + (6 if id == &"arcadia_aid_gold" else 8), "External funding must add budget immediately")


func _test_event_budget() -> void:
	for protected in [false, true]:
		var sim := _prepare()
		if protected:
			_play(sim, &"arcadia_recover_fdic")
		sim._fire_event(&"arcadia_ev_bank_panic")
		var cost := 8
		sim.state.budget = cost - 1
		var before := sim.state.indicators.duplicate()
		_expect(not sim.event_choice_available(0) and sim.event_choice_available(1), "Unaffordable bank rescue must have a free alternative")
		_expect(sim.apply_command(Command.resolve_event(0)).is_empty(), "Unaffordable rescue must be rejected")
		_expect(sim.state.budget == cost - 1 and sim.state.indicators == before and sim.state.pending_event != &"", "Failed rescue must not change funds, confidence or event state")
		sim.state.budget = cost
		_expect(sim.event_choice_available(0) and sim.event_choice_available(0), "Rescue preview must be repeatable without spending")
		_expect(sim.state.budget == cost, "Preview must not spend money")
		sim.apply_command(Command.resolve_event(0))
		_expect(sim.state.budget == 0 and sim.state.pending_event == &"", "Rescue must deduct the branch-specific budget cost")
	# At zero budget every event must still offer a way forward.
	for id in controller.events:
		var sim := _prepare()
		sim.state.budget = 0
		sim._fire_event(id)
		var definition: EconomyEventDef = controller.events[id]
		var choice := -1
		for index in definition.choices.size():
			if sim.event_choice_available(index):
				choice = index
				break
		_expect(not definition.has_choices() or choice >= 0, "Event must not trap a player without budget: %s" % id)
		sim.apply_command(Command.resolve_event(choice))
		_expect(sim.state.pending_event == &"" and sim.state.budget >= 0, "Free event resolution must advance without overdraft: %s" % id)


func _test_event_preview_ordering() -> void:
	var event := _preview_branch_event()
	var sim := _prepare()
	sim.event_db[event.id] = event
	sim.state.indicators[&"confidence"] = 45
	sim.state.budget = 10
	sim._fire_event(event.id)
	_expect(sim.event_choice_available(0), "Preview must apply earlier effects before selecting a branch")
	var events := sim.apply_command(Command.resolve_event(0))
	_expect(not events.is_empty() and sim.state.pending_event == &"", "An affordable previewed branch must resolve")
	_expect(sim.state.budget == 5 and sim.state.indicators[&"confidence"] == 55, "Resolution must select the same branch as the preview")
	# The same event is unaffordable when the earlier effect cannot cross the branch threshold.
	sim = _prepare()
	sim.event_db[event.id] = event
	sim.state.indicators[&"confidence"] = 45
	sim.state.budget = 4
	sim._fire_event(event.id)
	sim.economy.refresh_derived(sim.state)
	var before := sim.state.indicators.duplicate(true)
	_expect(not sim.event_choice_available(0), "Preview must reject the branch selected after earlier effects")
	_expect(sim.apply_command(Command.resolve_event(0)).is_empty(), "An unaffordable previewed branch must be rejected before execution")
	_expect(sim.state.budget == 4 and sim.state.indicators == before and sim.state.pending_event == event.id, "Rejected choice must not partially execute")
	sim.event_db.erase(event.id)


func _test_event_preview_isolation() -> void:
	var sim := _prepare()
	var event := _preview_isolation_event()
	sim.event_db[event.id] = event
	sim.state.indicators[&"confidence"] = 40
	sim.state.budget = 10
	sim._fire_event(event.id)
	var indicators := sim.state.indicators.duplicate(true)
	var hand := sim.state.hand.duplicate()
	var deck := sim.state.deck.duplicate()
	var discard := sim.state.discard.duplicate()
	var budget := sim.state.budget
	var rng_before := sim.rng.snapshot()
	_expect(sim.event_choice_available(-1), "No-choice event preview must be affordable")
	_expect(sim.state.indicators == indicators and sim.state.budget == budget, "Event preview must not change live indicators or budget")
	_expect(sim.state.hand == hand and sim.state.deck == deck and sim.state.discard == discard, "Event preview must not draw from the live deck")
	_expect(sim.state.pending_event == event.id, "Event preview must not resolve the pending event")
	_expect(sim.rng.snapshot().next_int(1000000) == rng_before.next_int(1000000), "Event preview must not consume live RNG")
	sim.event_db.erase(event.id)


func _preview_branch_event() -> EconomyEventDef:
	var event := EconomyEventDef.new()
	event.id = &"synthetic_preview_branch"
	event.title = "Preview branch"
	event.description = ""
	event.choices.append(EventChoice.from_dict({
		"label": "Pay after adjustment",
		"description": "",
		"effects": [
			{"kind": "adjust_indicator", "params": {"target": "confidence", "amount": 10}},
			{"kind": "branch", "params": {
				"condition": {"indicator": "confidence", "comparator": "ge", "value": 50},
				"then": [{"kind": "gain_budget", "params": {"amount": -5}}],
				"else": [{"kind": "gain_budget", "params": {"amount": -20}}],
			}},
		],
	}))
	return event


func _preview_isolation_event() -> EconomyEventDef:
	var event := EconomyEventDef.new()
	event.id = &"synthetic_preview_isolation"
	event.title = "Preview isolation"
	event.description = ""
	event.effects.append(Effect.from_dict({"kind": "adjust_indicator", "params": {"target": "confidence", "amount": 10}}))
	event.effects.append(Effect.from_dict({"kind": "draw_cards", "params": {"count": 2}}))
	event.effects.append(Effect.from_dict({"kind": "gain_budget", "params": {"amount": -5}}))
	return event


func _test_event_ui() -> void:
	var ui := GameUI.new()
	ui.theme = UiTheme.build()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	ui.setup(controller, &"example_country")
	ui._dispatch(Command.choose_reward([]))
	var sim := controller.simulation
	sim.state.budget = 0
	sim._fire_event(&"starter_supply")
	ui._render()
	await process_frame
	_expect(ui._overlay_panel.theme_type_variation == &"EventPanel", "Event modal must use its own warm palette")
	var panel_style: StyleBoxFlat = ui._overlay_panel.get_theme_stylebox("panel")
	_expect(panel_style.bg_color == UiTheme.EVENT_BG and panel_style.border_color == UiTheme.EVENT_BORDER, "Event panel must differ from ordinary white panels")
	var choices: Array[Button] = []
	for child in ui._overlay_box.get_children():
		if child is Button:
			_expect(child.theme_type_variation == &"EventChoice", "Event choices must use the matching warm palette")
			choices.append(child)
	_expect(choices.size() == 2 and choices[0].disabled and not choices[1].disabled, "Event UI must disable only the unaffordable option")
	if choices.size() == 2:
		_expect("预算不足" in choices[0].tooltip_text, "Disabled paid choice must explain the budget shortage")
	sim.state.budget = 2
	ui._render()
	for child in ui._overlay_box.get_children():
		if child is Button:
			_expect(not child.disabled, "Paid event choice must enable when budget is sufficient")
			child.pressed.emit()
			break
	_expect(sim.state.budget == 0 and sim.state.pending_event == &"", "Actual event UI click must pay budget and resolve")
	_expect(ui._overlay_panel.theme_type_variation == &"", "Event palette must reset after resolution")
	ui.free()
	await process_frame


func _test_relief() -> void:
	var targets := {&"starter_training": &"unemployment", &"arcadia_relief_ccc": &"unemployment", &"arcadia_relief_dole": &"confidence", &"arcadia_relief_farm": &"inflation"}
	for id in targets:
		var sim := _prepare()
		var before := sim.state.indicators.duplicate()
		_play(sim, id)
		for target in before:
			if sim.economy.derived_ids.has(target):
				continue
			_expect((sim.state.indicators[target] != before[target]) == (target == targets[id]), "Relief must change only its core indicator: %s / %s" % [id, target])


func _test_branches() -> void:
	for confidence in [30, 44, 45, 60]:
		var sim := _prepare()
		sim.state.indicators[&"confidence"] = confidence
		var before_gdp := float(sim.state.indicators[&"gdp"])
		_play(sim, &"arcadia_recover_bank_holiday")
		_expect(sim.state.indicators[&"confidence"] == confidence + (10 if confidence < 45 else 4), "Bank holiday uses the rebalanced confidence effect and unchanged threshold")
		_expect(is_equal_approx(sim.state.indicators[&"gdp"], before_gdp * 0.99), "Bank closure must preserve its direct output cost")
