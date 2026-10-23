extends SceneTree

## Sesja z hosta: ModuleHost.start_module z session_config → gra startuje od razu z tymi ustawieniami;
## koniec sesji → ModuleHostApi.finish_session → wpis w SessionResults (ścieżka testowa) i sygnał hosta.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_host_session.gd

const TEST_RESULTS := "user://test_bitbomber_sessions.json"

var _failed := 0
var _results: Array = []


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		_failed += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	SessionResults.save_path = TEST_RESULTS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_RESULTS))
	await process_frame
	var registry: Node = root.get_node("ModuleRegistry")
	var manifest: Dictionary = registry.get_by_id("bitbomber")
	_check(not manifest.is_empty(), "manifest BitBombera")

	# Przez load(): ModuleHost/ModuleHostApi używają autoloadów, których skrypt -s nie widzi przy kompilacji.
	var host: Node = load("res://scripts/core/module_host.gd").new()
	root.add_child(host)
	host.module_session_finished.connect(func(id: String, r: Dictionary): _results.append([id, r]))
	var layer := Node.new()
	root.add_child(layer)
	host.start_module(manifest, layer, {
		"humans": 1, "bots": 2, "mode": "kill", "kills_to_win": 1, "rounds_to_win": 1, "map": "forest_1", "difficulty": 1,
	})
	await _frames(10)

	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	_check(gm.host_session and gm.is_kill_mode() and gm.num_bots == 2 and gm.selected_map == "forest_1",
			"ustawienia z configu (kill, 2 boty, forest_1)")
	_check(gm.current_state == gm.GameState.PLAYING and rm.current_round == 1, "gra wystartowała bez menu modułu")

	rm.record_answer(1, true)
	rm.record_answer(1, false)
	rm.add_kill(2, 1)   # Bot 1 zabija gracza 1 → koniec rundy i sesji (1 zabójstwo, 1 runda)
	await process_frame
	_check(_results.size() == 1, "module_session_finished (%d)" % _results.size())
	if _results.size() == 1:
		var r: Dictionary = _results[0][1]
		_check(_results[0][0] == "bitbomber" and r.get("module_id") == "bitbomber" and r.has("finished_at"),
				"host dopisał module_id i finished_at")
		_check(r["winner"]["name"] == "Bot 1" and r["winner"]["is_bot"], "zwycięzca: %s" % [r["winner"]])
		_check(r["answers"] == {"correct": 1, "wrong": 1}, "odpowiedzi: %s" % [r["answers"]])
		_check((r["players"] as Array).size() == 3, "3 graczy w wyniku")
		print("INFO summary: ", r["summary"])
	var last: Dictionary = SessionResults.get_last("bitbomber")
	_check(str(last.get("summary", "")).contains("Bot 1"), "zapis w SessionResults: %s" % last.get("summary", ""))

	# Menu po sesji z hosta → wyjście do hosta.
	var exited := [false]
	host.module_exiting.connect(func(_id: String): exited[0] = true)
	paused = false
	gm.go_to_menu()
	await process_frame
	_check(exited[0] and not gm.host_session, "menu po sesji z hosta = wyjście z modułu")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_RESULTS))
	print("ALL OK" if _failed == 0 else "FAILED %d" % _failed)
	quit(_failed)
