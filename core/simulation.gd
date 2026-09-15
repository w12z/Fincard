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
var budget_db: Dictionary = {}
var group_db: Dictionary = {}

var card_reward_pool: Array[StringName] = []
var cabinet_reward_pool: Array[StringName] = []
var aid_reward_pool: Array[StringName] = []
var budget_pool: Array[StringName] = []

var _scenario: ScenarioDef


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
	_reset_state()
	state.scenario_id = _scenario.id
	for id in _scenario.indicators:
		economy.register_indicator(id)
		state.indicators[id] = float(_scenario.indicators[id])
	state.deck = _scenario.starting_deck.duplicate()
	rng.shuffle(state.deck)
	events.append(Event.new(Event.Kind.RUN_STARTED, {"scenario": _scenario.id}))
	for effect in _scenario.innate_modifiers:
		events.append_array(resolver.resolve(effect, state, rng))
	state.year = 1
	state.flags["opening_setup"] = true
	events.append_array(_offer_budget_or_finish())
	return trigger_engine.process(events, state, resolver, rng, _iteration_limit())


func apply_command(command: Command) -> Array[Event]:
	var events: Array[Event] = []
	match command.kind:
		Command.Kind.PLAY_CARD:
			events = _play_card(command.params)
		Command.Kind.END_TURN:
			events = _end_turn()
		Command.Kind.RESOLVE_EVENT:
			events = _resolve_event(command.params)
		Command.Kind.USE_AID:
			events = _use_aid(command.params)
		Command.Kind.CHOOSE_BUDGET:
			events = _choose_budget(command.params)
		Command.Kind.CHOOSE_REWARD:
			events = _choose_reward(command.params)
	return trigger_engine.process(events, state, resolver, rng, _iteration_limit())


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
	state.budget = 0
	state.political_capital = 0
	state.budget_scale = 0.0
	state.budget_plan = &""
	state.pending_budget_plans.clear()
	state.pending_event = &""
	state.pending_event_choices.clear()
	state.pending_rewards.clear()
	state.turn = 0
	state.turn_in_year = 0
	state.year = 0
	state.run_status = GameState.RunStatus.RUNNING
	turns.phase = TurnStateMachine.Phase.TURN_START


func _start_turn() -> Array[Event]:
	var events: Array[Event] = []
	events.append(turns.enter(TurnStateMachine.Phase.TURN_START, state))
	state.turn += 1
	state.turn_in_year += 1
	events.append(Event.new(Event.Kind.TURN_STARTED, {
		"turn": state.turn,
		"turn_in_year": state.turn_in_year,
		"year": state.year,
	}))
	_grant_turn_resources(events)
	events.append_array(_schedule_event())
	if state.pending_event != &"":
		return events
	events.append_array(_enter_main())
	return events


func _enter_main() -> Array[Event]:
	var events: Array[Event] = []
	events.append(turns.enter(TurnStateMachine.Phase.DRAW, state))
	events.append_array(_draw(int(rules.get("draw_per_turn", 0))))
	events.append(turns.enter(TurnStateMachine.Phase.MAIN, state))
	return events


func _schedule_event() -> Array[Event]:
	var events: Array[Event] = []
	if _scenario == null:
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
			allowed.append(id)
	if allowed.is_empty():
		return events
	var event_id: StringName = rng.pick(allowed)
	var chosen: EconomyEventDef = event_db[event_id]
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
	events.append_array(_enter_main())
	return events


func _end_turn() -> Array[Event]:
	var events: Array[Event] = []
	if state.pending_event != &"":
		return events
	if turns.phase != TurnStateMachine.Phase.MAIN:
		return events
	events.append(turns.enter(TurnStateMachine.Phase.TURN_END, state))
	for card_id in state.hand:
		state.discard.append(card_id)
	state.hand.clear()
	events.append_array(economy.tick(state, rng))
	events.append_array(_advance_modifiers())
	events.append(Event.new(Event.Kind.TURN_ENDED, {"turn": state.turn}))
	events.append_array(_check_end_conditions())
	if state.run_status != GameState.RunStatus.RUNNING:
		return events
	if state.turn_in_year >= int(rules.get("turns_per_year", 0)):
		events.append_array(_end_year())
	else:
		events.append_array(_start_turn())
	return events


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
	if state.budget < card.cost or state.political_capital < card.political_cost:
		return events
	state.budget -= card.cost
	state.political_capital -= card.political_cost
	if card.cost != 0:
		events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"budget", "amount": -card.cost}))
	if card.political_cost != 0:
		events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"political_capital", "amount": -card.political_cost}))
	state.hand.erase(card_id)
	events.append(Event.new(Event.Kind.CARD_PLAYED, {"card_id": card_id}))
	for effect in card.effects:
		events.append_array(resolver.resolve(effect, state, rng))
	state.discard.append(card_id)
	return events


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
		entry["uses"] = int(entry["uses"]) - 1
		if int(entry["uses"]) <= 0:
			state.aids.remove_at(index)
		events.append(Event.new(Event.Kind.AID_USED, {"aid": aid_id}))
		break
	return events


func _end_year() -> Array[Event]:
	var events: Array[Event] = []
	events.append(Event.new(Event.Kind.YEAR_ENDED, {"year": state.year}))
	events.append_array(_check_end_conditions())
	if state.run_status != GameState.RunStatus.RUNNING:
		return events
	var deadline := _scenario.goal.deadline_years if _scenario.goal != null else 0
	if deadline > 0 and state.year >= deadline:
		state.run_status = GameState.RunStatus.LOST
		events.append(Event.new(Event.Kind.RUN_LOST, {"reason": "deadline"}))
		return events
	events.append_array(_offer_budget_or_finish())
	return events


func _choose_budget(params: Dictionary) -> Array[Event]:
	var events: Array[Event] = []
	if state.pending_budget_plans.is_empty():
		return events
	var plan_id: StringName = params.get("plan_id", &"")
	if not state.pending_budget_plans.has(plan_id):
		return events
	var plan: BudgetPlanDef = budget_db[plan_id]
	state.budget_plan = plan_id
	state.pending_budget_plans.clear()
	events.append(Event.new(Event.Kind.BUDGET_CHOSEN, {"plan": plan_id}))
	events.append_array(_grant_year_resources(plan))
	events.append_array(_offer_rewards_or_finish())
	return events


func _grant_turn_resources(events: Array[Event]) -> void:
	var gain := int(rules.get("political_capital_per_turn", 0)) + int(economy.value(state, &"political_capital_gain"))
	if gain == 0:
		return
	state.political_capital += gain
	events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"political_capital", "amount": gain}))


func _grant_year_resources(plan: BudgetPlanDef) -> Array[Event]:
	var events: Array[Event] = []
	var budget_grant := 0
	var political_grant := 0
	if plan != null:
		budget_grant = plan.budget
		political_grant = plan.political_capital
		state.budget_scale = plan.scale
		for effect in plan.effects:
			events.append_array(resolver.resolve(effect, state, rng))
	else:
		if rules.has("base_budget"):
			budget_grant = int(rules["base_budget"])
		if rules.has("base_political_capital"):
			political_grant = int(rules["base_political_capital"])
		if rules.has("base_budget_scale"):
			state.budget_scale = float(rules["base_budget_scale"])
	state.budget = budget_grant
	state.political_capital += political_grant
	events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"budget", "amount": budget_grant}))
	events.append(Event.new(Event.Kind.RESOURCE_CHANGED, {"resource": &"political_capital", "amount": political_grant}))
	return events


func _offer_budget_or_finish() -> Array[Event]:
	var events: Array[Event] = []
	state.pending_budget_plans = _build_budget_options()
	if state.pending_budget_plans.is_empty():
		events.append_array(_grant_year_resources(null))
		events.append_array(_offer_rewards_or_finish())
		return events
	events.append(Event.new(Event.Kind.BUDGET_OFFERED, {"plans": _budget_options_info()}))
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
		events.append(Event.new(Event.Kind.YEAR_STARTED, {"year": state.year}))
		events.append_array(_start_turn())
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
	events.append_array(_finish_year_setup())
	return events


func _advance_year() -> Array[Event]:
	var events: Array[Event] = []
	state.turn_in_year = 0
	state.year += 1
	events.append(Event.new(Event.Kind.YEAR_STARTED, {"year": state.year}))
	events.append_array(_start_turn())
	return events


func _grant_reward(reward: Reward) -> Array[Event]:
	var events: Array[Event] = []
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
	var definition: CabinetDef = cabinet_db[cabinet_id]
	state.cabinets.append(definition)
	events.append(Event.new(Event.Kind.CABINET_APPOINTED, {"cabinet": cabinet_id}))
	for effect in definition.modifiers:
		events.append_array(resolver.resolve(effect, state, rng))
	return events


func _gain_aid(aid_id: StringName) -> Array[Event]:
	var events: Array[Event] = []
	if not aid_db.has(aid_id):
		return events
	var definition: AidDef = aid_db[aid_id]
	var found := false
	for entry in state.aids:
		if (entry["def"] as AidDef).id == aid_id:
			entry["uses"] = int(entry["uses"]) + definition.uses
			found = true
			break
	if not found:
		state.aids.append({"def": definition, "uses": definition.uses})
	events.append(Event.new(Event.Kind.AID_GAINED, {"aid": aid_id}))
	return events


func _check_end_conditions() -> Array[Event]:
	var events: Array[Event] = []
	if _scenario == null or _scenario.goal == null:
		return events
	if _scenario.goal.is_failed(state, economy):
		state.run_status = GameState.RunStatus.LOST
		events.append(Event.new(Event.Kind.RUN_LOST, {"reason": "loss_condition"}))
	elif _scenario.goal.is_achieved(state, economy):
		state.run_status = GameState.RunStatus.WON
		events.append(Event.new(Event.Kind.RUN_WON, {"reason": "goal_achieved"}))
	return events


func _build_budget_options() -> Array[StringName]:
	var result: Array[StringName] = []
	var source := _scenario.budget_pool if _scenario != null and not _scenario.budget_pool.is_empty() else budget_pool
	for id in source:
		if budget_db.has(id) and _member_allowed("budgets", id):
			result.append(id)
	return result


func _allowed_groups(type: String) -> Array:
	if _scenario == null:
		return []
	return _scenario.groups.get(type, [])


func _member_allowed(type: String, id: StringName) -> bool:
	var allowed: Array = _allowed_groups(type)
	if allowed.is_empty():
		return true
	for group_id in allowed:
		if group_db.has(group_id) and group_db[group_id].contains(type, id):
			return true
	return false


func groups_of(type: String, id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for group_id in group_db:
		var group: GroupDef = group_db[group_id]
		if group.contains(type, id):
			result.append(group_id)
	return result


func _budget_options_info() -> Array[Dictionary]:
	var info: Array[Dictionary] = []
	for id in state.pending_budget_plans:
		var plan: BudgetPlanDef = budget_db[id]
		info.append({
			"id": plan.id,
			"display_name": plan.display_name,
			"description": plan.description,
			"budget": plan.budget,
			"political_capital": plan.political_capital,
			"scale": plan.scale,
		})
	return info


func _build_year_end_rewards() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var option_count := int(rules.get("reward_option_count", 0))
	if option_count <= 0:
		return groups
	_add_reward_group(groups, Reward.Type.CARD, card_reward_pool, option_count)
	_add_reward_group(groups, Reward.Type.CABINET, cabinet_reward_pool, option_count)
	_add_reward_group(groups, Reward.Type.AID, aid_reward_pool, option_count)
	return groups


func _add_reward_group(groups: Array[Dictionary], type: int, pool: Array[StringName], count: int) -> void:
	var available: Array[StringName] = []
	for id in pool:
		if _reward_available(type, id):
			available.append(id)
	if available.is_empty():
		return
	var options: Array = []
	var candidates := available.duplicate()
	while options.size() < count and not candidates.is_empty():
		var index := rng.next_int(candidates.size())
		var id: StringName = candidates[index]
		candidates.remove_at(index)
		options.append(Reward.new(type, id, _reward_label(type, id)))
	groups.append({"type": type, "options": options})


func _reward_available(type: int, id: StringName) -> bool:
	match type:
		Reward.Type.CARD:
			return card_db.has(id) and _member_allowed("cards", id)
		Reward.Type.CABINET:
			for cabinet in state.cabinets:
				if cabinet.id == id:
					return false
			return cabinet_db.has(id) and _member_allowed("cabinets", id)
		Reward.Type.AID:
			return aid_db.has(id) and _member_allowed("aids", id)
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
		modifier.advance_turn()
		if modifier.is_expired():
			events.append(Event.new(Event.Kind.MODIFIER_EXPIRED, {
				"target": modifier.target,
				"source": modifier.source,
			}))
		else:
			kept.append(modifier)
	state.modifiers = kept
	return events


func _iteration_limit() -> int:
	return int(rules.get("trigger_iteration_limit", 0))
