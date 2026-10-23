extends SceneTree

## Muzyka: pliki z tools/gen_music.py są zapętlone (chunk smpl → LOOP_FORWARD), menu i runda włączają swoje utwory
## przez AudioService hosta.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_music.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _failed := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		_failed += 1


func _run() -> void:
	for track in ["menu", "battle"]:
		var stream := load(BBRuntime.path("resources/music/%s.wav" % track)) as AudioStreamWAV
		_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
				"%s.wav zapętlony (loop_mode %s)" % [track, stream.loop_mode if stream else "-"])

	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	for i in 3:
		await process_frame
	var audio: Node = root.get_node("AudioService")
	_check(audio.current_track == "bitbomber_menu", "menu modułu: %s" % audio.current_track)

	var gm: Node = root.get_node("GameManager")
	gm.selected_map = "classic"
	gm.start_game(1, 1)
	for i in 3:
		await process_frame
	_check(audio.current_track == "bitbomber_battle" and audio.music_player.playing, "runda: %s" % audio.current_track)

	print("ALL OK" if _failed == 0 else "FAILED %d" % _failed)
	quit(_failed)
