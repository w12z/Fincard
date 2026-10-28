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


static func coefficient(labels: Dictionary, id: StringName) -> String:
	return _lookup(labels, "coefficients", id)


static func modifier_target(labels: Dictionary, scope: StringName, id: StringName) -> String:
	if scope == Modifier.SCOPE_SPECIAL:
		return _lookup(labels, "special_modifiers", id)
	if scope == Modifier.SCOPE_REWARD:
		return _lookup(labels, "reward", id)
	if scope == Modifier.SCOPE_FISCAL:
		return _lookup(labels, "fiscal", id)
	if scope == Modifier.SCOPE_COEFFICIENT:
		return coefficient(labels, id)
	return indicator(labels, id)


static func resource(labels: Dictionary, id: StringName) -> String:
	return _lookup(labels, "resources", id)


static func event_name(labels: Dictionary, id: StringName) -> String:
	return _lookup(labels, "events", id)


static func card_type_name(labels: Dictionary, id: StringName) -> String:
	var table: Dictionary = labels.get("card_types", {})
	if table is Dictionary and table.has(String(id)):
		return str(table[String(id)])
	match String(id):
		"policy":
			return "政策"
		"reform":
			return "改革"
		_:
			return "投资与援助"


static func rarity_name(labels: Dictionary, id: StringName) -> String:
	return _lookup(labels, "rarities", id)


static func condition_text(labels: Dictionary, condition: Condition) -> String:
	return "%s %s %s" % [
		indicator(labels, condition.indicator),
		COMPARATORS.get(condition.comparator, "?"),
		fmt(condition.value),
	]


static func effect_text(labels: Dictionary, effect: Effect) -> String:
	var body := _effect_body(labels, effect)
	if effect.condition != null:
		return "若 %s：\n%s" % [condition_text(labels, effect.condition), _indent(body)]
	return body


static func effects_text(labels: Dictionary, effects: Array) -> String:
	var parts := PackedStringArray()
	for effect in effects:
		parts.append("• " + effect_text(labels, effect).replace("\n", "\n  "))
	return "\n".join(parts)


static func _indent(text: String) -> String:
	return "  " + text.replace("\n", "\n  ")


static func trigger_text(labels: Dictionary, trigger: Trigger) -> String:
	return "当「%s」时：\n%s" % [event_name(labels, _kind_name(trigger.on_kind)), _indent(effects_text(labels, trigger.effects))]


static func signed(value: float) -> String:
	return "+%s" % fmt(value) if value >= 0.0 else fmt(value)


static func fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	var text := "%.3f" % value
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	return text.trim_suffix(".")


static func _effect_body(labels: Dictionary, effect: Effect) -> String:
	var params := effect.params
	match effect.kind:
		Effect.Kind.ADJUST_INDICATOR:
			if bool(params.get("percent", false)):
				return "%s %s%%" % [indicator(labels, StringName(params.get("target", ""))), signed(float(params.get("amount", 0.0)))]
			return "%s %s" % [
				indicator(labels, StringName(params.get("target", ""))),
				signed(float(params.get("amount", 0.0))),
			]
		Effect.Kind.APPLY_MODIFIER:
			if params.get("scope", "indicator") == "special":
				var id := StringName(params.get("target", ""))
				if id == &"confidence_crash":
					return "【危机修正】" + _lookup(labels, "statuses", id)
				if id == &"next_investment_discount" and int(params.get("duration", 1)) == 1:
					return "本回合" + _lookup(labels, "statuses", id).trim_prefix("专项核准：")
				if id in [&"repeat_investment", &"investment_political_waiver"] and int(params.get("duration", 1)) == 1:
					var description := _lookup(labels, "statuses", id)
					return "本回合" + description.substr(description.find("：") + 1)
				return "【永久修正】" + _lookup(labels, "statuses", id) if int(params.get("duration", -1)) < 0 else "%d 回合内 %s ×%d" % [int(params.get("duration", 1)), modifier_target(labels, Modifier.SCOPE_SPECIAL, id), int(params.get("stacks", 1))]
			var target := modifier_target(labels, StringName(params.get("scope", "indicator")), StringName(params.get("target", "")))
			var duration := int(params.get("duration", 0))
			var window := "永久" if duration < 0 else "%d 回合内" % duration
			if duration >= 0 and params.get("scope", "indicator") == "fiscal":
				window = "接下来 %d 次财年发放" % duration
			match Modifier.op_from(params.get("op", "add")):
				Modifier.Op.MUL:
					return "%s %s ×%s" % [window, target, fmt(float(params.get("value", 0.0)))]
				Modifier.Op.OVERRIDE:
					return "%s %s 设为 %s" % [window, target, fmt(float(params.get("value", 0.0)))]
				_:
					return "%s %s %s" % [window, target, signed(float(params.get("value", 0.0)))]
		Effect.Kind.REMOVE_MODIFIER:
			if params.get("scope", "") == "coefficient" and params.get("target", "") == "gdp_auto" \
				and params.get("temporary_only", false) and params.get("positive_only", false):
				return "清除所有限期正向潜在增长修正（保留永久加成）"
			return "移除修正：%s" % modifier_target(labels, StringName(params.get("scope", "indicator")), StringName(params.get("target", "")))
		Effect.Kind.DRAW_CARDS:
			return "抽 %d 张牌" % int(params.get("count", 0))
		Effect.Kind.CHOOSE_DISCARD_DRAW:
			return "弃掉1张手牌，抽%d张牌" % int(params.get("draw_count", 2))
		Effect.Kind.GAIN_BUDGET:
			if params.has("per_investment_played"):
				return "本回合每已打出一张投资与援助类卡牌，获得%d预算，最多%d预算" % [int(params["per_investment_played"]), int(params.get("cap", 4))]
			return "财政预算 %s" % signed(float(params.get("amount", 0.0)))
		Effect.Kind.GAIN_POLITICAL_CAPITAL:
			return "政治行动点 %s" % signed(float(params.get("amount", 0.0)))
		Effect.Kind.BRANCH:
			var raw_condition = params.get("condition")
			var branch_condition := ""
			if raw_condition is Dictionary:
				branch_condition = condition_text(labels, Condition.from_dict(raw_condition))
			var then_text := effects_text(labels, parse_effects(params.get("then", [])))
			var else_text := effects_text(labels, parse_effects(params.get("else", [])))
			if branch_condition == "":
				return then_text
			if else_text == "":
				return "若 %s：\n%s" % [branch_condition, _indent(then_text)]
			return "若 %s：\n%s\n否则：\n%s" % [branch_condition, _indent(then_text), _indent(else_text)]
		Effect.Kind.GRANT_STATUS:
			return "【永久能力】" + _lookup(labels, "statuses", StringName(params.get("status", "")))
		Effect.Kind.GAIN_CARD:
			return "获得卡牌「%s」" % _lookup(labels, "cards", StringName(params.get("card", "")))
	return "未知效果"


static func parse_effects(raw: Variant) -> Array[Effect]:
	var effects: Array[Effect] = []
	if not (raw is Array):
		return effects
	for entry in raw:
		if entry is Dictionary:
			effects.append(Effect.from_dict(entry))
	return effects


static func _kind_name(kind: int) -> StringName:
	return Event.name_of(kind)


static func _lookup(labels: Dictionary, section: String, id: StringName) -> String:
	var table = labels.get(section)
	if table is Dictionary and table.has(id):
		return str(table[id])
	if table is Dictionary and table.has(String(id)):
		return str(table[String(id)])
	return String(id)
