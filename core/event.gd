class_name Event
extends RefCounted

enum Kind {
	TURN_STARTED,
	TURN_ENDED,
	CARD_PLAYED,
	CARD_GAINED,
	CARDS_DRAWN,
	INDICATOR_CHANGED,
	MODIFIER_APPLIED,
	MODIFIER_EXPIRED,
	RESOURCE_CHANGED,
	RUN_STARTED,
	YEAR_STARTED,
	YEAR_ENDED,
	EVENT_TRIGGERED,
	EVENT_RESOLVED,
	CABINET_APPOINTED,
	AID_USED,
	AID_GAINED,
	BUDGET_OFFERED,
	BUDGET_CHOSEN,
	REWARD_OFFERED,
	REWARD_CHOSEN,
	RUN_WON,
	RUN_LOST,
	CUSTOM,
}

const KIND_NAMES := {
	"turn_started": Kind.TURN_STARTED,
	"turn_ended": Kind.TURN_ENDED,
	"card_played": Kind.CARD_PLAYED,
	"card_gained": Kind.CARD_GAINED,
	"cards_drawn": Kind.CARDS_DRAWN,
	"indicator_changed": Kind.INDICATOR_CHANGED,
	"modifier_applied": Kind.MODIFIER_APPLIED,
	"modifier_expired": Kind.MODIFIER_EXPIRED,
	"resource_changed": Kind.RESOURCE_CHANGED,
	"run_started": Kind.RUN_STARTED,
	"year_started": Kind.YEAR_STARTED,
	"year_ended": Kind.YEAR_ENDED,
	"event_triggered": Kind.EVENT_TRIGGERED,
	"event_resolved": Kind.EVENT_RESOLVED,
	"cabinet_appointed": Kind.CABINET_APPOINTED,
	"aid_used": Kind.AID_USED,
	"aid_gained": Kind.AID_GAINED,
	"budget_offered": Kind.BUDGET_OFFERED,
	"budget_chosen": Kind.BUDGET_CHOSEN,
	"reward_offered": Kind.REWARD_OFFERED,
	"reward_chosen": Kind.REWARD_CHOSEN,
	"run_won": Kind.RUN_WON,
	"run_lost": Kind.RUN_LOST,
	"custom": Kind.CUSTOM,
}

var kind: int
var params: Dictionary

static var _name_by_kind: Dictionary = {}


func _init(p_kind: int, p_params: Dictionary = {}) -> void:
	kind = p_kind
	params = p_params


static func kind_from(value) -> int:
	if value is String:
		return KIND_NAMES.get(value, Kind.CUSTOM)
	return int(value)


static func name_of(kind: int) -> StringName:
	if _name_by_kind.is_empty():
		for key in KIND_NAMES:
			_name_by_kind[KIND_NAMES[key]] = StringName(key)
	return _name_by_kind.get(kind, &"")
