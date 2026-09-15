class_name TurnStateMachine
extends RefCounted

enum Phase { TURN_START, DRAW, MAIN, TURN_END }

const ALLOWED := {
	Phase.TURN_START: [Phase.DRAW, Phase.MAIN],
	Phase.DRAW: [Phase.MAIN],
	Phase.MAIN: [Phase.TURN_END, Phase.MAIN],
	Phase.TURN_END: [Phase.TURN_START],
}

var phase: int = Phase.TURN_START


func can_transition(to: int) -> bool:
	return ALLOWED.get(phase, []).has(to)


func enter(to: int, state: GameState) -> Event:
	phase = to
	state.phase = to
	return Event.new(Event.Kind.PHASE_CHANGED, {"phase": to})
