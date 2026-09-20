class_name DataLoader
extends RefCounted


static func load_dir(path: String, factory: Callable) -> Dictionary:
	var db: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir == null:
		return db
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".json"):
			var data = ConfigLoader.load_json(path.path_join(file))
			if data is Dictionary:
				var definition = factory.call(data)
				if definition != null and "id" in definition:
					db[definition.id] = definition
		file = dir.get_next()
	dir.list_dir_end()
	return db
