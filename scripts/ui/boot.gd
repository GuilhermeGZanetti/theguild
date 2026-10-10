extends Node
## Entry point: applies the theme, then opens the title screen.
## Command line: --screenshot-test=<name> runs a scripted capture (tools only).


func _ready() -> void:
	get_tree().root.theme = UITheme.build()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--trailer="):
			# one shot of the trailer, filmed by tools/trailer/make.py
			var tree := get_tree()
			tree.create_timer(240.0, true, false, true).timeout.connect(func(): tree.quit(3))
			Scenes.go("res://scenes/trailer.tscn", {"shot": a.substr(10)})
			return
		if a.begins_with("--shot="):
			# watchdog: developer captures never hang
			var tree := get_tree()
			var shot := a.substr(7)
			tree.create_timer(400.0 if shot == "flow" else 90.0, true, false, true).timeout.connect(func(): tree.quit(3))
			if shot == "flow":
				var flow: Node = load("res://scripts/ui/dev_flow.gd").new()
				tree.root.add_child.call_deferred(flow)
				flow.run.call_deferred()
				return
			Scenes.go("res://scenes/dev_shots.tscn", {"shot": shot})
			return
	Scenes.go("res://scenes/title.tscn")
