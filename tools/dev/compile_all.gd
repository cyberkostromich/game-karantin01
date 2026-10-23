extends SceneTree
func _initialize() -> void:
	var bad := 0
	for dir in ["res://src/sim", "res://src/view", "res://src/ui", "res://src/input", "res://src/main", "res://src/net", "res://src/autoload", "res://tests"]:
		for f in _files(dir):
			var s: Variant = load(f)
			if s == null or (s is GDScript and not (s as GDScript).can_instantiate()):
				print("SCRIPT ERROR in ", f)
				bad += 1
	print("COMPILED, bad=", bad)
	quit()

func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files(dir.path_join(sub)))
	return out
