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
		"deficit_spending": "deficit", "political_capital_gain": "political",
	}
	return texture("res://assets/icons/modifiers/%s.svg" % names.get(key, "modifier"))
