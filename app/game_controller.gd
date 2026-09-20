class_name GameController
extends Node

const CARD_DIR := "res://data/cards"
const SCENARIO_DIR := "res://data/scenarios"
const EVENT_DIR := "res://data/events"
const CABINET_DIR := "res://data/cabinets"
const AID_DIR := "res://data/aids"
const BUDGET_DIR := "res://data/budgets"
const GROUP_DIR := "res://data/groups"
const RULES_PATH := "res://data/config/rules.json"
const REWARD_POOLS_PATH := "res://data/config/reward_pools.json"
const ECONOMY_PATH := "res://data/config/economy.json"
const LABELS_PATH := "res://data/config/labels.json"

@export var seed_value: int = 0

var simulation: Simulation
var cards: Dictionary = {}
var scenarios: Dictionary = {}
var events: Dictionary = {}
var cabinets: Dictionary = {}
var aids: Dictionary = {}
var budgets: Dictionary = {}
var groups: Dictionary = {}
var rules: Dictionary = {}
var economy_config: Dictionary = {}
var labels: Dictionary = {}


func _ready() -> void:
	cards = DataLoader.load_dir(CARD_DIR, func(d): return CardDef.from_dict(d))
	scenarios = DataLoader.load_dir(SCENARIO_DIR, func(d): return ScenarioDef.from_dict(d))
	events = DataLoader.load_dir(EVENT_DIR, func(d): return EconomyEventDef.from_dict(d))
	cabinets = DataLoader.load_dir(CABINET_DIR, func(d): return CabinetDef.from_dict(d))
	aids = DataLoader.load_dir(AID_DIR, func(d): return AidDef.from_dict(d))
	budgets = DataLoader.load_dir(BUDGET_DIR, func(d): return BudgetPlanDef.from_dict(d))
	groups = DataLoader.load_dir(GROUP_DIR, func(d): return GroupDef.from_dict(d))
	rules = ConfigLoader.load_json(RULES_PATH)
	economy_config = ConfigLoader.load_json(ECONOMY_PATH)
	labels = ConfigLoader.load_json(LABELS_PATH)
	simulation = Simulation.new(seed_value)
	simulation.card_db = cards
	simulation.scenario_db = scenarios
	simulation.event_db = events
	simulation.cabinet_db = cabinets
	simulation.aid_db = aids
	simulation.budget_db = budgets
	simulation.group_db = groups
	simulation.rules = rules
	EconomyBuilder.build(simulation.economy, economy_config, rules)
	_load_pools()


func available_scenarios() -> Array:
	return scenarios.values()


func start_run(scenario_id: StringName) -> Array[Event]:
	return simulation.start_run(scenario_id)


func dispatch(command: Command) -> Array[Event]:
	return simulation.apply_command(command)


func _load_pools() -> void:
	var pools = ConfigLoader.load_json(REWARD_POOLS_PATH)
	if not pools is Dictionary:
		pools = {}
	simulation.card_reward_pool = _resolve_pool(pools, "cards", cards)
	simulation.cabinet_reward_pool = _resolve_pool(pools, "cabinets", cabinets)
	simulation.aid_reward_pool = _resolve_pool(pools, "aids", aids)
	simulation.budget_pool = _resolve_pool(pools, "budgets", budgets)


func _resolve_pool(pools: Dictionary, key: String, fallback: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var configured = pools.get(key)
	if configured is Array and not configured.is_empty():
		for id in configured:
			result.append(StringName(id))
		return result
	for id in fallback.keys():
		result.append(id)
	return result
