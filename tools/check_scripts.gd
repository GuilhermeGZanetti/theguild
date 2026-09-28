extends SceneTree
## Loads every script and scene so parse errors surface without playing.
## godot --headless --path . -s res://tools/check_scripts.gd


func _init() -> void:
	await process_frame
	var bad := 0
	for dir in ["res://scripts", "res://scenes"]:
		for f in _walk(dir):
			var r = load(f)
			if r == null:
				print("FAILED: ", f)
				bad += 1
			elif r is GDScript and not r.can_instantiate():
				print("CANNOT INSTANTIATE: ", f)
				bad += 1
	print("check_scripts done, failures: ", bad)
	quit(1 if bad > 0 else 0)


func _walk(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_walk(dir + "/" + sub))
	return out
