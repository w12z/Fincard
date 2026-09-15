class_name TriggerEngine
extends RefCounted

const FALLBACK_ITERATION_LIMIT := 16


func process(events: Array[Event], state: GameState, resolver: EffectResolver, rng: Rng, iteration_limit: int) -> Array[Event]:
	var all := events.duplicate()
	var queue := events.duplicate()
	var limit := iteration_limit if iteration_limit > 0 else FALLBACK_ITERATION_LIMIT
	var iterations := 0
	while not queue.is_empty() and iterations < limit:
		iterations += 1
		var next: Array[Event] = []
		for event in queue:
			for cabinet in state.cabinets:
				for trigger in cabinet.triggers:
					if trigger.on_kind != event.kind:
						continue
					for effect in trigger.effects:
						next.append_array(resolver.resolve(effect, state, rng))
		all.append_array(next)
		queue = next
	return all
