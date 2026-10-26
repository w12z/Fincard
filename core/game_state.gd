class_name GameState
extends RefCounted

enum RunStatus { RUNNING, WON, LOST }

var indicators: Dictionary = {}
var prev_indicators: Dictionary = {}
var modifiers: Array[Modifier] = []
var deck: Array[StringName] = []
var hand: Array[StringName] = []
var discard: Array[StringName] = []
var cabinets: Array[CabinetDef] = []
var aids: Array[Dictionary] = []
var budget: int = 0
var political_capital: int = 0
var turn: int = 0
var turn_in_year: int = 0
var year: int = 0
var phase: int = 0
var run_status: int = RunStatus.RUNNING
var seed_value: int = 0
var scenario_id: StringName = &""
var base_annual_income: int = 0
var base_budget_retention: float = 0.5
var pending_event: StringName = &""
var pending_event_choices: Array[Dictionary] = []
var pending_rewards: Array[Dictionary] = []
var flags: Dictionary = {}
var statuses: Array[StringName] = []
var cards_played_this_turn: int = 0
var played_cards_this_turn: Array[StringName] = []
var investments_played_this_turn: int = 0
var statuses_triggered_this_turn: Array[StringName] = []


func snapshot() -> GameState:
	var copy := GameState.new()
	# Script properties contain only game state, not RefCounted's engine properties.
	for property in get_script().get_script_property_list():
		var value = get(property["name"])
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		copy.set(property["name"], value)
	copy.modifiers.clear()
	for modifier in modifiers:
		copy.modifiers.append(Modifier.new(modifier.target, modifier.op, modifier.value, modifier.remaining_turns, modifier.source, modifier.scope))
	return copy


func draw_card(rng: Rng) -> bool:
	if deck.is_empty():
		reshuffle(rng)
	if deck.is_empty():
		return false
	hand.append(deck.pop_back())
	return true


func reshuffle(rng: Rng) -> void:
	if discard.is_empty():
		return
	deck.append_array(discard)
	discard.clear()
	rng.shuffle(deck)
