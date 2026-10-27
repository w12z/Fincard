class_name Simulation
extends RefCounted

var state: GameState
var rng: Rng
var economy: EconomyModel
var resolver: EffectResolver
var turns: TurnStateMachine
var trigger_engine: TriggerEngine

var rules: Dictionary = {}
var card_db: Dictionary = {}
var scenario_db: Dictionary = {}
var event_db: Dictionary = {}
var cabinet_db: Dictionary = {}
var aid_db: Dictionary = {}
var group_db: Dictionary = {}
var status_db: Dictionary = {}

var card_reward_pool: Array[StringName] = []
var cabinet_reward_pool: Array[StringName] = []
var aid_reward_pool: Array[StringName] = []

var _scenario: ScenarioDef
var _skip_card_choices: bool = false


func _init(seed_value: int) -> void:
	state = GameState.new()
	state.seed_value = seed_value
	rng = Rng.new(seed_value)
	economy = EconomyModel.new()
	resolver = EffectResolver.new()
	resolver.economy = economy
	turns = TurnStateMachine.new()
	trigger_engine = TriggerEngine.new()


func start_run(scenario_id: StringName) -> Array[Event]:
	var events: Array[Event] = []
	if not scenario_db.has(scenario_id):
		push_warning("Unknown scenario: %s" % scenario_id)
		return events
	_scenario = scenario_db[scenario_id]
	economy.set_scenario_coefficients(_scenario.economy_overrides)
	economy.reset_bounds()
	economy.apply_bounds_overrides(_scenario.bounds_overrides)
	_reset_state()
	state.scenario_id = _scenario.id
	state.base_annual_income = _scenario.annual_income
	state.base_budget_retention = float(rules.get("budget_retention", 0.5))
	economy.set_active_indicators(_scenario.indicators.keys())
	for id in _scenario.indicators:
		state.indicators[id] = float(_scenario.indicators[id])
	state.deck = _scenario.starting_deck.duplicate()
	rng.shuffle(state.deck)
	events.append(Event.new(Event.Kind.RUN_STARTED, {"scenario": _scenario.id}))
	for effect in _scenario.innate_modifiers:
		events.append_array(resolver.resolve(effect, state, rng))
	economy.refresh_derived(state)
	state.year = 1
	state.flags["opening_setup"] = true
	events.append_array(_offer_rewards_or_finish())
	return events


func apply_command(command: Command) -> Array[Event]:
	var events: Array[Event] = []
	if state.run_status != GameState.RunStatus.RUNNING:
		return events
	if command.kind in [Command.Kind.PLAY_CARD, Command.Kind.USE_AID, Command.Kind.END_TURN] and not _can_act():
		return events
	match command.kind:
		Command.Kind.PLAY_CARD:
			events = _play_card(command.params)
		Command.Kind.END_TURN:
			events = _end_turn()
		Command.Kind.RESOLVE_EVENT:
			events = _resolve_event(command.params)
		Command.Kind.USE_AID:
			events = _use_aid(command.params)
		Command.Kind.CHOOSE_REWARD:
			events = _choose_reward(command.params)
		Command.Kind.CHOOSE_RETAINED_CARD:
			events = _choose_retained_card(command.params)
		Command.Kind.CHOOSE_REVIEW_CARD:
			events = _choose_review_card(command.params)
		Command.Kind.CLAIM_REWARD:
			events = _claim_reward(command.params)
	if command.kind in [Command.Kind.PLAY_CARD, Command.Kind.USE_AID, Command.Kind.RESOLVE_EVENT, Command.Kind.CHOOSE_REVIEW_CARD]:
		events = trigger_engine.process(events, state, resolver, rng, _iteration_limit())
		economy.refresh_derived(state)
		events.append_array(_check_end_conditions(false))
	return events


func forecast_next_turn() -> GameState:
	if state.run_status != GameState.RunStatus.RUNNING or not _can_act():
		return null
	# Use the actual turn pipeline on an isolated state/RNG. Future rewards and
	# unresolved event choices are excluded; existing cabinet triggers still run.
	var preview := _clone_for_preview()
	preview.rules["random_event_chance"] = 0.0
	preview.rules["reward_option_count"] = 0
	preview._skip_card_choices = true
	preview._end_turn()
	return preview.state


func _clone_for_preview() -> Simulation:
	# Clone everything resolution can observe so previews never mutate the live run.
	var preview := Simulation.new(state.seed_value)
	preview.state = state.snapshot()
	preview.rng = rng.snapshot()
	preview.rules = rules.duplicate(true)
	preview._scenario = _scenario
	preview.turns.phase = turns.phase
	preview.card_db = card_db
	preview.event_db = event_db
	preview.cabinet_db = cabinet_db
	preview.aid_db = aid_db
	preview.group_db = group_db
	preview.status_db = status_db
	preview.resolver.economy = preview.economy
	preview.resolver.card_db = card_db
	preview.resolver.status_db = status_db
	preview.economy.indicator_ids = economy.indicator_ids.duplicate()
	preview.economy.derived_ids = economy.derived_ids.duplicate()
	preview.economy.equations = economy.equations.duplicate()
	preview.economy.derived = economy.derived.duplicate()
	preview.economy.bounds = economy.bounds.duplicate(true)
	preview.economy.base_bounds = economy.base_bounds.duplicate(true)
	preview.economy.base_coefficients = economy.base_coefficients.duplicate()
	preview.economy.scenario_coefficients = economy.scenario_coefficients.duplicate()
	return preview


func _can_act() -> bool:
	return turns.phase == TurnStateMachine.Phase.MAIN and state.pending_event == &"" \
		and state.pending_rewards.is_empty() and not state.flags.get("pending_retain", false) \
		and not state.flags.get("pending_review", false)


func _reset_state() -> void:
	state.indicators.clear()
	state.prev_indicators.clear()
	state.modifiers.clear()
	state.deck.clear()
	state.hand.clear()
	state.discard.clear()
	state.cabinets.clear()
	state.aids.clear()
	state.flags.clear()
	state.cards_played_this_turn = 0
	state.played_cards_this_turn.clear()
	state.investments_played_this_turn = 0
	state.budget = 0
	state.political_capital = 0
	state.base_annual_income = 0
	state.base_budget_retention = 0.5
	state.pending_event = &""
	state.pending_event_choices.clear()
	state.pending_rewards.clear()
	state.turn = 0
	state.turn_in_year = 0
	state.year = 0
	state.run_status = GameState.RunStatus.RUNNING
	turns.phase = TurnStateMachine.Phase.TURN_START


func _start_turn(year_started: bool = false) -> Array[Event]:
	var events: Array[Event] = []
	turns.enter(TurnStateMachine.Phase.TURN_START, state)
	state.turn += 1
	state.turn_in_year += 1
	state.cards_played_this_turn = 0
	state.played_cards_this_turn.clear()
	state.investments_played_this_turn = 0
	state.flags["types_played_this_turn"] = []
	_grant_turn_resources(events)
	if year_started:
		var year_events: Array[Event] = [Event.new(Event.Kind.YEAR_STARTED, {"year": state.year})]
		events.append_array(trigger_engine.process(year_events, state, resolver, rng, _iteration_limit()))
	var turn_events: Array[Event] = []
	turn_events.append(Event.new(Event.Kind.TURN_STARTED, {
		"turn": state.turn,
		"turn_in_year": state.turn_in_year,
		"year": state.year,
	}))
	events.append_array(trigger_engine.process(turn_events, state, resolver, rng, _iteration_limit()))
	for modifier in StatusRules.active_modifiers(state):
		if modifier.rule != &"next_turn_replay" or int(modifier.data.get("queued_turn", state.turn + 1)) > state.turn:
			continue
		var replay_id := StringName(modifier.data.get("queued_card", ""))
		modifier.data.erase("queued_card")
		modifier.data.erase("queued_turn")
		if replay_id == &"":
			continue
		for layer in modifier.stacks:
			events.append_array(_replay_card(replay_id))
		economy.refresh_derived(state)
		events.append_array(_check_end_conditions(false))
		if state.run_status != GameState.RunStatus.RUNNING:
			return events
	events.append_array(_enter_main())
	if not _skip_card_choices and not state.hand.is_empty() and StatusRules.has_rule(state, status_db, &"start_turn_review"):
		state.flags["pending_review"] = true
	else:
		events.append_array(_schedule_event())
	economy.refresh_derived(state)
	return events


func _enter_main() -> Array[Event]:
	var events: Array[Event] = []
	turns.enter(TurnStateMachine.Phase.DRAW, state)
	events.append_array(_draw(int(rules.get("draw_per_turn", 0))))
	turns.enter(TurnStateMachine.Phase.MAIN, state)
	return events


func _schedule_event() -> Array[Event]:
	var events: Array[Event] = []
	if _scenario == null:
		return events
	var scheduled: StringName = _scenario.scheduled_events.get(state.turn, &"")
	if scheduled != &"" and event_db.has(scheduled):
		return _fire_event(scheduled)
	if rng.next_float() >= float(rules.get("random_event_chance", 0.35)):
		return events
	var candidates: Array[StringName] = []
	if not _scenario.event_pool.is_empty():
		candidates = _scenario.event_pool.duplicate()
	else:
		for id in event_db:
			candidates.append(id)
	var allowed: Array[StringName] = []
	for id in candidates:
		if event_db.has(id) and _member_allowed("events", id):
			var definition: EconomyEventDef = event_db[id]
			if state.turn < definition.min_turn or (definition.max_turn > 0 and state.turn > definition.max_turn):
				continue
			var last_turn := int(state.flags.get("event_last:" + String(id), -1000))
			if state.turn - last_turn <= definition.cooldown:
				continue
			allowed.append(id)
	if allowed.is_empty():
		return events
	return _fire_event(rng.pick(allowed))


func _fire_event(event_id: StringName) -> Array[Event]:
	var events: Array[Event] = []
	var chosen: EconomyEventDef = event_db[event_id]
	state.flags["event_last:" + String(event_id)] = state.turn
	state.pending_event = event_id
	state.pending_event_choices.clear()
	for choice in chosen.choices:
		state.pending_event_choices.append({"label": choice.label, "description": choice.description})
	events.append(Event.new(Event.Kind.EVENT_TRIGGERED, {
		"event": event_id,
		"title": chosen.title,
		"description": chosen.description,
		"choices": state.pending_event_choices.duplicate(),
	}))
	return events


func _resolve_event(params: Dictionary) -> Array[Event]:
	var events: Array[Event] = []
	if state.pending_event == &"" or not event_db.has(state.pending_event):
		return events
	if not event_choice_available(int(params.get("choice_index", -1))):
		return events
	var definition: EconomyEventDef = event_db[state.pending_event]
	if definition.has_choices():
		var index := int(params.get("choice_index", -1))
		if index < 0 or index >= definition.choices.size():
			return events
		for effect in definition.choices[index].effects:
			events.append_array(resolver.resolve(effect, state, rng))
	else:
		for effect in definition.effects:
			events.append_array(resolver.resolve(effect, state, rng))
	events.append(Event.new(Event.Kind.EVENT_RESOLVED, {"event": definition.id}))
	state.pending_event = &""
	state.pending_event_choices.clear()
	turns.enter(TurnStateMachine.Phase.MAIN, state)
	return events


func event_choice_available(choice_index: int) -> bool:
	if state.pending_event == &"" or not event_db.has(state.pending_event):
		return false
	var definition: EconomyEventDef = event_db[state.pending_event]
	if not definition.has_choices():
		return _effects_affordable(definition.effects)
	if choice_index < 0 or choice_index >= definition.choices.size():
		return false
	return _effects_affordable(definition.choices[choice_index].effects)


func can_spend_budget(amount: int) -> bool:
	return amount <= 0 or state.budget - amount >= budget_floor()


func budget_floor() -> int:
	return -annual_income() if StatusRules.allows_deficit(state, status_db) else 0


func _effects_affordable(effects: Array) -> bool:
	if effects.is_empty():
		return true
	# Resolve the whole effect list against an isolated simulation so earlier
	# effects can change the indicator values and modifiers that later branches read.
	var preview := _clone_for_preview()
	for effect: Effect in effects:
		preview.resolver.resolve(effect, preview.state, preview.rng)
	return preview.state.budget >= mini(state.budget, preview.budget_floor())


func _end_turn() -> Array[Event]:
	if state.pending_event != &"":
		return []
	if turns.phase != TurnStateMachine.Phase.MAIN:
		return []
	if not _skip_card_choices and not state.hand.is_empty() and StatusRules.has_rule(state, status_db, &"retain_card"):
		state.flags["pending_retain"] = true
		return []
	return _finish_turn()


func _choose_retained_card(params: Dictionary) -> Array[Event]:
	if not state.flags.get("pending_retain", false):
		return []
	var index := int(params.get("hand_index", -1))
	if index < -1 or index >= state.hand.size():
		return []
	var retained: StringName = state.hand[index] if index >= 0 else &""
	if index >= 0:
		state.hand.remove_at(index)
	state.flags.erase("pending_retain")
	return _finish_turn(retained)


func _choose_review_card(params: Dictionary) -> Array[Event]:
	if not state.flags.get("pending_review", false):
		return []
	var index := int(params.get("hand_index", -1))
	if index < -1 or index >= state.hand.size():
		return []
	state.flags.erase("pending_review")
	var events: Array[Event] = []
	if index >= 0:
		state.discard.append(state.hand[index])
		state.hand.remove_at(index)
		events.append_array(_draw(2))
	events.append_array(_schedule_event())
	return events


func _finish_turn(retained: StringName = &"") -> Array[Event]:
	var events: Array[Event] = []
	turns.enter(TurnStateMachine.Phase.TURN_END, state)
	for card_id in state.hand:
		state.discard.append(card_id)
	state.hand.clear()
	if retained != &"":
		state.hand.append(retained)
	for modifier in StatusRules.active_modifiers(state):
		if modifier.rule == &"save_political":
			modifier.data["saved"] = mini(modifier.amount * modifier.stacks, maxi(0, state.political_capital))
	events.append_array(economy.tick(state, rng))
	events.append(Event.new(Event.Kind.TURN_ENDED, {"turn": state.turn}))
	events = trigger_engine.process(events, state, resolver, rng, _iteration_limit())
	events.append_array(_advance_modifiers())
	economy.refresh_derived(state)
	events.append_array(_check_end_conditions())
	if state.run_status != GameState.RunStatus.RUNNING:
		return events
	if state.turn_in_year >= int(rules.get("turns_per_year", 0)):
		events.append_array(_end_year())
	else:
		events.append_array(_start_turn())
	return events


func card_costs(card_id: StringName) -> Dictionary:
	var card: CardDef = card_db.get(card_id)
	if card == null:
		return {}
	return StatusRules.card_costs(card, state, status_db)


func _play_card(params: Dictionary) -> Array[Event]:
	var events: Array[Event] = []
	if state.run_status != GameState.RunStatus.RUNNING:
		return events
	if turns.phase != TurnStateMachine.Phase.MAIN:
		return events
	var card_id: StringName = params.get("card_id", &"")
	if not state.hand.has(card_id):
		return events
	var card: CardDef = card_db.get(card_id)
	if card == null:
		return events
	var costs := card_costs(card_id)
	var budget_cost := int(costs["budget"])
	var political_cost := int(costs["political"])
	if not can_spend_budget(budget_cost) or (political_cost > 0 and state.political_capital < political_cost):
		return events
	var active_before := StatusRules.active_modifiers(state)
	state.budget -= budget_cost
	state.political_capital -= political_cost
	state.cards_played_this_turn += 1
	state.played_cards_this_turn.append(card_id)
	if card.card_type == &"investment":
		state.investments_played_this_turn += 1
	var types: Array = state.flags.get("types_played_this_turn", [])
	if not types.has(card.card_type):
		types.append(card.card_type)
	state.flags["types_played_this_turn"] = types
	if budget_cost != 0:
		events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"budget", "amount": -budget_cost}))
	if political_cost != 0:
		events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"political_capital", "amount": -political_cost}))
	for id in costs["sources"]:
		var modifier := StatusRules.find_modifier(state, id)
		if modifier != null:
			events.append(StatusRules.mark_triggered(modifier, state))
	state.hand.erase(card_id)
	events.append(Event.new(Event.Kind.CARD_PLAYED, {"card_id": card_id}))
	for effect in card.effects:
		events.append_array(resolver.resolve(effect, state, rng))
	if card.once_per_run:
		state.flags["enacted:" + String(card_id)] = true
		_remove_all_copies(card_id)
	else:
		state.discard.append(card_id)
	for modifier in active_before:
		match modifier.rule:
			&"repeat_next_card":
				var repeats := modifier.stacks
				modifier.stacks = 0
				for layer in repeats:
					events.append_array(_replay_card(card_id))
			&"third_card_draw":
				if state.cards_played_this_turn == 3:
					events.append_array(_trigger_draw_modifier(modifier, modifier.amount * modifier.stacks))
			&"investment_draw":
				if card.card_type == &"investment":
					var progress := int(modifier.data.get("progress", 0)) + 1
					if progress >= modifier.amount:
						progress -= modifier.amount
						events.append_array(_trigger_draw_modifier(modifier, modifier.stacks))
					modifier.data["progress"] = progress
			&"all_types_refund":
				if types.has(&"investment") and types.has(&"policy") and types.has(&"reform") and int(modifier.data.get("triggered_turn", -1)) != state.turn:
					events.append(StatusRules.mark_triggered(modifier, state))
					events.append_array(resolver.resolve(Effect.from_dict({"kind": "gain_political_capital", "params": {"amount": modifier.amount * modifier.stacks}}), state, rng))
			&"next_turn_replay":
				if state.cards_played_this_turn == 1:
					modifier.data["queued_card"] = card_id
					modifier.data["queued_turn"] = state.turn + 1
					events.append(StatusRules.mark_triggered(modifier, state))
	for modifier in state.modifiers.duplicate():
		if modifier.is_expired():
			state.modifiers.erase(modifier)
	return events


func _trigger_draw_modifier(modifier: Modifier, count: int) -> Array[Event]:
	var events: Array[Event] = [StatusRules.mark_triggered(modifier, state)]
	events.append_array(_draw(count))
	return events


func _replay_card(card_id: StringName) -> Array[Event]:
	var card: CardDef = card_db.get(card_id)
	if card == null:
		return []
	var events: Array[Event] = [Event.new(Event.Kind.CARD_REPLAYED, {"card_id": card_id})]
	state.played_cards_this_turn.append(card_id)
	for effect in card.effects:
		events.append_array(resolver.resolve(effect, state, rng))
	return events


func _remove_all_copies(card_id: StringName) -> void:
	while state.hand.has(card_id):
		state.hand.erase(card_id)
	while state.deck.has(card_id):
		state.deck.erase(card_id)
	while state.discard.has(card_id):
		state.discard.erase(card_id)


func _use_aid(params: Dictionary) -> Array[Event]:
	var events: Array[Event] = []
	var aid_id: StringName = params.get("aid_id", &"")
	for index in range(state.aids.size()):
		var entry: Dictionary = state.aids[index]
		var definition: AidDef = entry["def"]
		if definition.id != aid_id or int(entry["uses"]) <= 0:
			continue
		for effect in definition.effects:
			events.append_array(resolver.resolve(effect, state, rng))
		state.aids.remove_at(index)
		events.append(Event.new(Event.Kind.AID_USED, {"aid": aid_id}))
		for modifier in StatusRules.active_modifiers(state):
			if modifier.rule == &"aid_card_repeat" and int(modifier.data.get("used_turn", -1)) != state.turn:
				modifier.data["used_turn"] = state.turn
				events.append_array(resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
					"scope": "special", "target": "replay", "stacks": modifier.stacks, "duration": 1, "source": String(modifier.source),
				}}), state, rng))
		break
	return events


func _end_year() -> Array[Event]:
	var events: Array[Event] = []
	events.append(Event.new(Event.Kind.YEAR_ENDED, {"year": state.year}))
	events = trigger_engine.process(events, state, resolver, rng, _iteration_limit())
	economy.refresh_derived(state)
	events.append_array(_check_end_conditions())
	if state.run_status != GameState.RunStatus.RUNNING:
		return events
	var deadline := _scenario.goal.deadline_years if _scenario.goal != null else 0
	if deadline > 0 and state.year >= deadline:
		state.run_status = GameState.RunStatus.LOST
		state.flags["loss_reason"] = "deadline"
		events.append(Event.new(Event.Kind.RUN_LOST, {"reason": "deadline"}))
		return events
	events.append_array(_offer_rewards_or_finish())
	return events


func _grant_turn_resources(events: Array[Event]) -> void:
	var previous := state.political_capital
	state.political_capital = political_capital_per_turn()
	for modifier in StatusRules.active_modifiers(state):
		if modifier.rule == &"save_political":
			state.political_capital += int(modifier.data.get("saved", 0))
			modifier.data.erase("saved")
	var changes: Array[Event] = [Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"political_capital", "amount": state.political_capital - previous})]
	events.append_array(trigger_engine.process(changes, state, resolver, rng, _iteration_limit()))


func political_capital_per_turn() -> int:
	return maxi(0, int(rules.get("political_capital_per_turn", 0)) + int(economy.value(state, &"political_capital_gain")))


func fiscal_value(target: StringName, base: float) -> float:
	return modified_value(Modifier.SCOPE_FISCAL, target, base)


func modified_value(scope: StringName, target: StringName, base: float) -> float:
	var value := base
	for modifier in state.modifiers:
		if modifier.scope != scope or modifier.target != target or modifier.is_expired():
			continue
		match modifier.op:
			Modifier.Op.ADD: value += modifier.effective_value()
			Modifier.Op.MUL: value *= modifier.effective_value()
			Modifier.Op.OVERRIDE: value = modifier.effective_value()
	return value


func annual_income() -> int:
	return maxi(0, int(floor(fiscal_value(&"annual_income", state.base_annual_income))))


func budget_retention() -> float:
	return clampf(fiscal_value(&"budget_retention", state.base_budget_retention), 0.0, 1.0)


func _grant_year_resources() -> Array[Event]:
	var events: Array[Event] = []
	var previous_budget := state.budget
	var carried_budget := state.budget if state.budget < 0 else int(floor(state.budget * budget_retention()))
	state.budget = carried_budget + annual_income()
	events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"budget", "amount": state.budget - previous_budget}))
	# Fiscal duration counts income payments, never turns.
	for modifier in state.modifiers.duplicate():
		if modifier.scope == Modifier.SCOPE_FISCAL:
			modifier.advance_turn()
			if modifier.is_expired():
				state.modifiers.erase(modifier)
				events.append(Event.new(Event.Kind.MODIFIER_EXPIRED, {"target": modifier.target, "scope": modifier.scope, "source": modifier.source}))
	return events


func _offer_rewards_or_finish() -> Array[Event]:
	var events: Array[Event] = []
	state.pending_rewards = _build_year_end_rewards()
	if state.pending_rewards.is_empty():
		events.append_array(_finish_year_setup())
		return events
	events.append(Event.new(Event.Kind.REWARD_OFFERED, {"groups": state.pending_rewards.duplicate(true)}))
	return events


func _finish_year_setup() -> Array[Event]:
	var events: Array[Event] = []
	if state.flags.get("opening_setup", false):
		state.flags.erase("opening_setup")
		events.append_array(_grant_year_resources())
		events = trigger_engine.process(events, state, resolver, rng, _iteration_limit())
		events.append_array(_start_turn(true))
		return events
	events.append_array(_advance_year())
	return events


func _choose_reward(params: Dictionary) -> Array[Event]:
	var events: Array[Event] = []
	if state.pending_rewards.is_empty():
		return events
	var picks: Array = params.get("picks", [])
	for group_index in range(state.pending_rewards.size()):
		var group: Dictionary = state.pending_rewards[group_index]
		var options: Array = group.get("options", [])
		var pick := int(picks[group_index]) if group_index < picks.size() else -1
		if pick < 0 or pick >= options.size():
			continue
		events.append_array(_grant_reward(options[pick]))
	state.pending_rewards.clear()
	events.append(Event.new(Event.Kind.REWARD_CHOSEN, {"picks": picks}))
	events = trigger_engine.process(events, state, resolver, rng, _iteration_limit())
	economy.refresh_derived(state)
	events.append_array(_finish_year_setup())
	return events


func _claim_reward(params: Dictionary) -> Array[Event]:
	var events: Array[Event] = []
	var group_index := int(params.get("group_index", -1))
	if group_index < 0 or group_index >= state.pending_rewards.size():
		return events
	var token := str(params.get("token", ""))
	if token != "" and token != str(state.pending_rewards[group_index].get("token", "")):
		return events
	var options: Array = state.pending_rewards[group_index].get("options", [])
	var option_index := int(params.get("option_index", -1))
	if option_index < -1 or option_index >= options.size():
		return events
	if option_index >= 0:
		var reward: Reward = options[option_index]
		if not _reward_available(reward.type, reward.id):
			return events
		events.append_array(_grant_reward(reward))
	state.pending_rewards.remove_at(group_index)
	events.append(Event.new(Event.Kind.REWARD_CHOSEN, {"group_index": group_index, "option_index": option_index}))
	events = trigger_engine.process(events, state, resolver, rng, _iteration_limit())
	economy.refresh_derived(state)
	events.append_array(_check_end_conditions(false))
	if state.pending_rewards.is_empty() and state.run_status == GameState.RunStatus.RUNNING:
		events.append_array(_finish_year_setup())
	return events


func _advance_year() -> Array[Event]:
	var events: Array[Event] = []
	state.turn_in_year = 0
	state.year += 1
	events.append_array(_grant_year_resources())
	events = trigger_engine.process(events, state, resolver, rng, _iteration_limit())
	events.append_array(_start_turn(true))
	return events


func _grant_reward(reward: Reward) -> Array[Event]:
	var events: Array[Event] = []
	if not _reward_available(reward.type, reward.id):
		return events
	match reward.type:
		Reward.Type.CARD:
			state.deck.append(reward.id)
			events.append(Event.new(Event.Kind.CARD_GAINED, {"card_id": reward.id}))
		Reward.Type.CABINET:
			events.append_array(_appoint_cabinet(reward.id))
		Reward.Type.AID:
			events.append_array(_gain_aid(reward.id))
	return events


func _appoint_cabinet(cabinet_id: StringName) -> Array[Event]:
	var events: Array[Event] = []
	if not cabinet_db.has(cabinet_id):
		return events
	for cabinet in state.cabinets:
		if cabinet.id == cabinet_id:
			return events
	var definition: CabinetDef = cabinet_db[cabinet_id]
	state.cabinets.append(definition)
	events.append(Event.new(Event.Kind.CABINET_APPOINTED, {"cabinet": cabinet_id}))
	for effect in definition.modifiers:
		events.append_array(resolver.resolve(effect, state, rng))
	for index in definition.triggers.size():
		var trigger: Trigger = definition.triggers[index]
		events.append_array(resolver.resolve(Effect.from_dict({"kind": "apply_modifier", "params": {
			"scope": "special", "target": "%s_trigger_%d" % [definition.id, index], "rule": "event_effects",
			"duration": -1, "source": definition.display_name,
			"data": {"on_kind": trigger.on_kind, "effects": trigger.effects},
		}}), state, rng))
	var legendary_ids: Array[StringName] = []
	for cabinet in state.cabinets:
		if cabinet.rarity == &"legendary" and not legendary_ids.has(cabinet.id):
			legendary_ids.append(cabinet.id)
	if legendary_ids.size() >= 2 and card_db.has(&"special_national_strategy"):
		events.append_array(resolver.resolve(Effect.from_dict({
			"kind": "gain_card", "params": {"card": "special_national_strategy"},
		}), state, rng))
	return events


func aid_capacity() -> int:
	return maxi(0, int(rules.get("aid_capacity", 3)))


func aid_count() -> int:
	return state.aids.size()


func aid_gain_amount(aid_id: StringName) -> int:
	var definition: AidDef = aid_db.get(aid_id)
	if definition == null:
		return 0
	return mini(maxi(0, definition.uses), maxi(0, aid_capacity() - aid_count()))


func _gain_aid(aid_id: StringName) -> Array[Event]:
	var events: Array[Event] = []
	if not aid_db.has(aid_id):
		return events
	var definition: AidDef = aid_db[aid_id]
	var amount := aid_gain_amount(aid_id)
	if amount <= 0:
		return events
	# Grant separate single-use items, including duplicates of the same type.
	for i in amount:
		state.aids.append({"def": definition, "uses": 1})
	events.append(Event.new(Event.Kind.AID_GAINED, {"aid": aid_id, "amount": amount}))
	return events


func _check_end_conditions(allow_win: bool = true) -> Array[Event]:
	var events: Array[Event] = []
	if state.run_status != GameState.RunStatus.RUNNING or _scenario == null or _scenario.goal == null:
		return events
	var goal := _scenario.goal
	if goal.is_failed(state, economy):
		state.run_status = GameState.RunStatus.LOST
		state.flags["loss_reason"] = "loss_condition"
		events.append(Event.new(Event.Kind.RUN_LOST, {"reason": "loss_condition"}))
		return events
	if not allow_win or (goal.after_turn > 0 and state.turn <= goal.after_turn):
		return events
	if goal.is_achieved(state, economy):
		state.run_status = GameState.RunStatus.WON
		events.append(Event.new(Event.Kind.RUN_WON, {"reason": "goal_achieved"}))
	return events


func _allowed_groups(type: String) -> Array:
	if _scenario == null:
		return []
	if _scenario.groups.has(type):
		return _scenario.groups[type]
	return _scenario.groups.get("*", [])


func _member_allowed(type: String, id: StringName) -> bool:
	var allowed: Array = _allowed_groups(type)
	if allowed.is_empty():
		return true
	var type_name := StringName(type)
	for group_id in allowed:
		if not group_db.has(group_id):
			continue
		var group: GroupDef = group_db[group_id]
		if group.type == type_name and group.contains(id):
			return true
	return false


func groups_of(type: String, id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var type_name := StringName(type)
	for group_id in group_db:
		var group: GroupDef = group_db[group_id]
		if group.type == type_name and group.contains(id):
			result.append(group_id)
	return result


func _build_year_end_rewards() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	state.flags["reward_batch"] = int(state.flags.get("reward_batch", 0)) + 1
	var option_count := int(rules.get("reward_option_count", 0))
	if option_count <= 0:
		return groups
	var card_groups := maxi(1, int(rules.get("card_reward_groups", 1)))
	for i in card_groups:
		_add_reward_group(groups, Reward.Type.CARD, card_reward_pool, option_count)
	_add_reward_group(groups, Reward.Type.CABINET, cabinet_reward_pool, 2)
	_add_reward_group(groups, Reward.Type.AID, aid_reward_pool, option_count)
	return groups


func _add_reward_group(groups: Array[Dictionary], type: int, pool: Array[StringName], count: int) -> void:
	var available: Array[StringName] = []
	for id in pool:
		if _reward_available(type, id):
			if type == Reward.Type.CARD and card_db[id].once_per_run:
				var already_offered := false
				for group in groups:
					for option: Reward in group["options"]:
						if option.type == type and option.id == id:
							already_offered = true
				if already_offered:
					continue
			available.append(id)
	if available.is_empty():
		return
	var options: Array = []
	var candidates := available.duplicate()
	while options.size() < count and not candidates.is_empty():
		var id: StringName = _pick_rarity_reward(candidates, cabinet_db if type == Reward.Type.CABINET else card_db) if type in [Reward.Type.CARD, Reward.Type.CABINET] else rng.pick(candidates)
		if id == &"":
			break
		candidates.erase(id)
		options.append(Reward.new(type, id, _reward_label(type, id)))
	if not options.is_empty():
		groups.append({"type": type, "options": options, "token": "%d:%d" % [int(state.flags.get("reward_batch", 0)), groups.size()]})


func base_rarity_weight(rarity: StringName) -> float:
	var defaults := {"common": 20.0, "rare": 5.0, "legendary": 1.0}
	return float(rules.get("card_rarity_weights", {}).get(String(rarity), defaults.get(String(rarity), 0.0)))


func rarity_weight(rarity: StringName) -> float:
	if not CardDef.REWARD_RARITIES.has(rarity):
		return 0.0
	return maxf(0.0, modified_value(Modifier.SCOPE_REWARD, rarity, base_rarity_weight(rarity)))


func _pick_reward_card(candidates: Array) -> StringName:
	return _pick_rarity_reward(candidates, card_db)


func _pick_rarity_reward(candidates: Array, definitions: Dictionary) -> StringName:
	# Cards and cabinets share the exact same effective rarity weights.
	# Empty/zero-weight tiers are excluded; card counts never skew tier odds.
	var buckets := {}
	var total := 0.0
	for rarity in CardDef.REWARD_RARITIES:
		var cards: Array[StringName] = []
		for id in candidates:
			if definitions.has(id) and definitions[id].rarity == rarity:
				cards.append(id)
		if not cards.is_empty() and rarity_weight(rarity) > 0.0:
			buckets[rarity] = cards
			total += rarity_weight(rarity)
	if total <= 0.0:
		return &""
	var roll := rng.next_float() * total
	for rarity in buckets:
		roll -= rarity_weight(rarity)
		if roll < 0.0:
			return rng.pick(buckets[rarity])
	return rng.pick(buckets.values().back())


func _reward_available(type: int, id: StringName) -> bool:
	match type:
		Reward.Type.CARD:
			if card_db.has(id) and card_db[id].once_per_run:
				if state.flags.get("enacted:" + String(id), false) or state.deck.has(id) or state.hand.has(id) or state.discard.has(id):
					return false
			return card_db.has(id) and CardDef.REWARD_RARITIES.has(card_db[id].rarity) and _member_allowed("cards", id)
		Reward.Type.CABINET:
			for cabinet in state.cabinets:
				if cabinet.id == id:
					return false
			return cabinet_db.has(id) and CardDef.REWARD_RARITIES.has(cabinet_db[id].rarity) and _member_allowed("cabinets", id)
		Reward.Type.AID:
			return aid_gain_amount(id) > 0 and _member_allowed("aids", id)
	return false


func _reward_label(type: int, id: StringName) -> String:
	match type:
		Reward.Type.CARD:
			var card: CardDef = card_db[id]
			return card.display_name if card.display_name != "" else String(id)
		Reward.Type.CABINET:
			var cabinet: CabinetDef = cabinet_db[id]
			return cabinet.display_name if cabinet.display_name != "" else String(id)
		Reward.Type.AID:
			var aid: AidDef = aid_db[id]
			return aid.display_name if aid.display_name != "" else String(id)
	return String(id)


func _draw(count: int) -> Array[Event]:
	var events: Array[Event] = []
	var drawn := 0
	while drawn < count and state.draw_card(rng):
		drawn += 1
	if drawn > 0:
		events.append(Event.new(Event.Kind.CARDS_DRAWN, {"count": drawn}))
	return events


func _advance_modifiers() -> Array[Event]:
	var events: Array[Event] = []
	var kept: Array[Modifier] = []
	for modifier in state.modifiers:
		if modifier.scope != Modifier.SCOPE_FISCAL and modifier.is_active(state.turn):
			modifier.advance_turn()
		if modifier.is_expired():
			events.append(Event.new(Event.Kind.MODIFIER_EXPIRED, {
				"target": modifier.target,
				"scope": modifier.scope,
				"source": modifier.source,
			}))
		else:
			kept.append(modifier)
	state.modifiers = kept
	return events


func _iteration_limit() -> int:
	return int(rules.get("trigger_iteration_limit", 0))
