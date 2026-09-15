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
var budget_scale: float = 0.0
var turn: int = 0
var turn_in_year: int = 0
var year: int = 0
var phase: int = 0
var run_status: int = RunStatus.RUNNING
var seed_value: int = 0
var scenario_id: StringName = &""
var budget_plan: StringName = &""
var pending_budget_plans: Array[StringName] = []
var pending_event: StringName = &""
var pending_event_choices: Array[Dictionary] = []
var pending_rewards: Array[Dictionary] = []
var flags: Dictionary = {}


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
