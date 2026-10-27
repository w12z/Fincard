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
			for modifier in state.modifiers.duplicate():
				if modifier.scope != Modifier.SCOPE_SPECIAL or modifier.rule != &"event_effects" or not modifier.is_active(state.turn):
					continue
				if int(modifier.data.get("on_kind", -1)) != event.kind:
					continue
				for layer in modifier.stacks:
					for raw in modifier.data.get("effects", []):
						var effect: Effect = raw if raw is Effect else Effect.from_dict(raw)
						next.append_array(resolver.resolve(effect, state, rng))
		all.append_array(next)
		queue = next
	return all
