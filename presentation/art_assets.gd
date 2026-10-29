class_name ArtAssets
extends RefCounted

static var _textures: Dictionary = {}


static func texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if ResourceLoader.exists(path):
		var imported := ResourceLoader.load(path) as Texture2D
		if imported != null:
			_textures[path] = imported
			return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	var result := ImageTexture.create_from_image(image)
	_textures[path] = result
	return result


static func card_picture(id: StringName, height: float = 86) -> TextureRect:
	var picture := TextureRect.new()
	picture.name = "Illustration"
	picture.texture = texture("res://assets/cards/%s.png" % id)
	picture.custom_minimum_size = Vector2(0, height)
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


static func event_picture(id: StringName, height: float = 160) -> TextureRect:
	var illustration := texture("res://assets/events/%s.png" % id)
	if illustration == null:
		return null
	var picture := TextureRect.new()
	picture.name = "EventIllustration"
	picture.texture = illustration
	picture.custom_minimum_size = Vector2(0, height)
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


static func modifier_icon(key: String) -> Texture2D:
	var names := {
		"gdp_auto": "growth", "growth": "growth", "gdp": "growth", "inflation_target": "target",
		"natural_unemployment": "employment", "unemployment": "employment", "interest_rate": "interest",
		"annual_income": "income", "budget_retention": "reserve", "confidence": "confidence",
		"inflation": "target", "infl_anchor": "anchor", "u_revert": "recovery",
		"common": "reward", "rare": "reward", "legendary": "reward",
		"first_card_political_free": "free", "first_investment_discount": "fund", "third_card_draw": "draw",
		"second_card_free": "free", "all_types_refund": "rotation", "investment_draw": "review",
		"aid_card_repeat": "repeat", "repeat_next_card": "repeat", "next_turn_replay": "repeat",
		"retain_card": "retain", "start_turn_review": "review", "save_political": "political",
		"deficit_spending": "deficit", "political_capital_gain": "political", "turn_draw_bonus": "draw",
		"growth_confidence_bonus": "growth", "market_overheating": "review", "negative_growth_confidence": "confidence",
		"next_investment_discount": "fund",
		"second_investment_discount": "fund", "first_growth_extension": "anchor", "second_investment_budget": "income",
		"first_job_confidence": "employment", "confidence_growth_start": "growth", "first_confidence_employment": "confidence",
		"third_card_budget": "income", "first_political_policy_discount": "political", "second_policy_discount": "fund",
		"repeat_next_investment": "repeat", "next_investment_political_discount": "political",
		"first_card_discount": "fund", "last_card_next_turn": "repeat",
	}
	return texture("res://assets/icons/modifiers/%s.svg" % names.get(key, "modifier"))
