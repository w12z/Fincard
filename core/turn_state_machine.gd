class_name TurnStateMachine
extends RefCounted

enum Phase { TURN_START, DRAW, MAIN, TURN_END }

var phase: int = Phase.TURN_START


func enter(to: int, state: GameState) -> void:
	phase = to
	state.phase = to
