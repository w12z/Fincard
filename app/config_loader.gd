class_name ConfigLoader
extends RefCounted


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_warning("Failed to parse JSON: %s" % path)
		return {}
	return parsed
