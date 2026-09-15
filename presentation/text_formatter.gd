class_name TextFormatter
extends RefCounted

const COMPARATORS := {
	Condition.Comparator.GE: "≥",
	Condition.Comparator.LE: "≤",
	Condition.Comparator.GT: ">",
	Condition.Comparator.LT: "<",
	Condition.Comparator.EQ: "=",
}


static func indicator(labels: Dictionary, id: StringName) -> String:
	return _lookup(labels, "indicators", id)


static func resource(labels: Dictionary, id: StringName) -> String:
	return _lookup(labels, "resources", id)


static func event_name(labels: Dictionary, id: StringName) -> String:
	return _lookup(labels, "events", id)


static func condition_text(labels: Dictionary, condition: Condition) -> String:
	return "%s %s %s" % [
		indicator(labels, condition.indicator),
		COMPARATORS.get(condition.comparator, "?"),
		fmt(condition.value),
	]


static func effect_text(labels: Dictionary, effect: Effect) -> String:
	var body := _effect_body(labels, effect)
	if effect.condition != null:
		return "若 %s，%s" % [condition_text(labels, effect.condition), body]
	return body


static func effects_text(labels: Dictionary, effects: Array) -> String:
	var parts := PackedStringArray()
	for effect in effects:
		parts.append(effect_text(labels, effect))
	return "；".join(parts)


static func trigger_text(labels: Dictionary, trigger: Trigger) -> String:
	return "当「%s」时：%s" % [event_name(labels, _kind_name(trigger.on_kind)), effects_text(labels, trigger.effects)]


static func signed(value: float) -> String:
	return "+%s" % fmt(value) if value >= 0.0 else fmt(value)


static func fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value


static func _effect_body(labels: Dictionary, effect: Effect) -> String:
	var params := effect.params
	match effect.kind:
		Effect.Kind.ADJUST_INDICATOR:
			return "%s %s" % [
				indicator(labels, StringName(params.get("target", ""))),
				signed(float(params.get("amount", 0.0))),
			]
		Effect.Kind.APPLY_MODIFIER:
			var target := indicator(labels, StringName(params.get("target", "")))
			var duration := int(params.get("duration", 0))
			var window := "永久" if duration < 0 else "%d 回合内" % duration
			var op: String = params.get("op", "add")
			match op:
				"mul":
					return "%s %s ×%s" % [window, target, fmt(float(params.get("value", 0.0)))]
				"override":
					return "%s %s 设为 %s" % [window, target, fmt(float(params.get("value", 0.0)))]
				_:
					return "%s %s %s" % [window, target, signed(float(params.get("value", 0.0)))]
		Effect.Kind.REMOVE_MODIFIER:
			return "移除修正：%s" % indicator(labels, StringName(params.get("target", "")))
		Effect.Kind.DRAW_CARDS:
			return "抽 %d 张牌" % int(params.get("count", 0))
		Effect.Kind.GAIN_BUDGET:
			return "财政预算 %s" % signed(float(params.get("amount", 0.0)))
		Effect.Kind.GAIN_POLITICAL_CAPITAL:
			return "政治行动点 %s" % signed(float(params.get("amount", 0.0)))
	return "未知效果"


static func _kind_name(kind: int) -> StringName:
	for key in Event.KIND_NAMES:
		if Event.KIND_NAMES[key] == kind:
			return StringName(key)
	return &""


static func _lookup(labels: Dictionary, section: String, id: StringName) -> String:
	var table = labels.get(section)
	if table is Dictionary and table.has(id):
		return str(table[id])
	if table is Dictionary and table.has(String(id)):
		return str(table[String(id)])
	return String(id)
