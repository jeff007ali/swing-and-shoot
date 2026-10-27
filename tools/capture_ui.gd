extends SceneTree
## UI screenshots for design review: opens one menu screen and saves a frame to the user folder
## (user://ui_shots/). Needs a window (not --headless). Run once per screen:
##   godot --path . --resolution 1920x1080 -s res://tools/capture_ui.gd -- screen=<name>
## Screens: menu, play, lan, lan_host, lan_browse, lan_wait, settings

const OUT: String = "user://ui_shots/"

var screen := "menu"
var frames := 0
var node: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("screen="):
			screen = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var scene := "res://src/ui/lobby_screen.tscn" if screen.begins_with("lan") else "res://src/ui/main_menu.tscn"
	node = (load(scene) as PackedScene).instantiate()
	node.set("change_scene", false)
	root.add_child(node)
	process_frame.connect(_frame)


func _frame() -> void:
	frames += 1
	if frames == 5:
		_open()
	elif frames == 45:
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path(OUT + screen + ".png")
		img.save_png(path)
		print("saved ", path)
		root.get_node("/root/Net").call("leave")
		quit()


func _open() -> void:
	var net: Node = root.get_node("/root/Net")
	match screen:
		"play":
			node.call("_open_play")
		"settings":
			node.call("_open_settings")
		"lan_host":
			node.call("_host")
		"lan_browse":
			node.call("_browse")
			var discovery: Node = net.get("discovery")
			var games: Dictionary = discovery.get("games")
			games["192.168.1.23"] = {"info": NetProtocol.parse_beacon(NetProtocol.beacon("Sam", 2, "koth", "solar")), "seen": Time.get_ticks_msec() + 60000}
			games["192.168.1.40"] = {"info": NetProtocol.parse_beacon(NetProtocol.beacon("Riya", 1, "ffa", "station")), "seen": Time.get_ticks_msec() + 60000}
			discovery.emit_signal("games_changed")
		"lan_wait":
			net.set("players", [{"peer": 1, "name": "Sam"}, {"peer": 2, "name": "You"}])
			net.set("mode", "koth")
			net.set("arena", "solar")
			node.call("_show", 3)
