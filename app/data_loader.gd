class_name DataLoader
extends RefCounted


static func load_dir(path: String, factory: Callable) -> Dictionary:
	var db: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir == null:
		return db
	var files := dir.get_files()
	files.sort()
	for file in files:
		if file.ends_with(".json"):
			var data = ConfigLoader.load_json(path.path_join(file))
			if data is Dictionary:
				var definition = factory.call(data)
				if definition != null and "id" in definition:
					if db.has(definition.id):
						push_error("Duplicate content ID: %s (%s)" % [definition.id, file])
						continue
					db[definition.id] = definition
	return db
