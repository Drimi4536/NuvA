extends Node
## Все скрипты проекта собираются: godot --headless --path . res://tools/parse_all.tscn → PARSE OK

func _ready() -> void:
	var bad := 0
	for f in _list("res://scripts"):
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			push_error("не собирается: " + f)
			bad += 1
	for f in _list("res://scenes"):
		if f.ends_with(".tscn") and load(f) == null:
			push_error("сцена не грузится: " + f)
			bad += 1
	print("PARSE OK" if bad == 0 else "PARSE FAIL: %d" % bad)
	get_tree().quit(0 if bad == 0 else 1)


func _list(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out += _list(dir + "/" + d)
	return out
