extends SceneTree

## Cała gra: moduł → start sesji 1 człowiek + 3 boty → SMOKE_SECONDS sekund gry.
## Gracz-człowiek stoi; liczy się, że nic nie sypie błędami (sprawdź SCRIPT ERROR w wyjściu).
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_smoke.gd
## env: SMOKE_SECONDS (domyślnie 60), SMOKE_BOTS (3), SMOKE_DIFF (2)

const BBRuntime = preload("../scripts/bb_runtime.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var seconds := int(OS.get_environment("SMOKE_SECONDS")) if OS.has_environment("SMOKE_SECONDS") else 60
	var bots := int(OS.get_environment("SMOKE_BOTS")) if OS.has_environment("SMOKE_BOTS") else 3
	var diff := int(OS.get_environment("SMOKE_DIFF")) if OS.has_environment("SMOKE_DIFF") else 2

	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	await process_frame

	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	rm.round_ended.connect(func(w: int): print("round_ended winner=%d t=%.1f" % [w, rm._round_timer]))
	rm.last_chance_triggered.connect(func(p: int): print("last_chance p=%d" % p))
	gm.bot_difficulty = diff
	gm.start_game(1, bots)

	var frames := seconds * 60
	var boxes_start := -1
	for i in frames:
		await physics_frame
		if i == 5:
			boxes_start = gm.game_node._current_map.breakable_cells.size()
		if i % 600 == 0:
			var alive := 0
			for p in get_nodes_in_group("players"):
				if p.is_alive:
					alive += 1
			print("t=%ds alive=%d bombs=%d state=%d" % [i / 60, alive, get_nodes_in_group("bomb").size(), gm.current_state])

	var map: Node = gm.game_node._current_map
	if map and map.get("breakable_cells") != null:
		print("skrzynki: %d -> %d" % [boxes_start, map.breakable_cells.size()])
	print("SMOKE DONE")
	quit(0)
