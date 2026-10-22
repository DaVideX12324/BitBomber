extends SceneTree

## Nagła śmierć: limit rundy 3 s → bloki spiralą → runda musi się skończyć (dawniej po limicie wisiała).
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_sudden_death.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _failed := 0
var _ended := false
var _winner := -100
var _last_chance := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		_failed += 1


func _run() -> void:
	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	rm.round_ended.connect(func(w: int): _ended = true; _winner = w)
	rm.last_chance_triggered.connect(func(_p: int): _last_chance = true)
	gm.selected_map = "forest_1"
	gm.start_game(1, 3)
	rm.round_time_limit = 3.0

	var frames := 0
	while not rm.sudden_death and frames < 60 * 10:
		await physics_frame
		frames += 1
	_check(rm.sudden_death, "nagła śmierć po limicie (%.1f s)" % (frames / 60.0))
	var arena: Node = gm.game_node._current_map
	await physics_frame
	_check(not arena.sudden_death_danger().is_empty(), "ostrzeżenie o kolejnych polach")

	frames = 0
	while not _ended and frames < 60 * 60:
		await physics_frame
		frames += 1
	_check(_ended, "runda zakończona %.1f s po starcie nagłej śmierci (zwycięzca %d)" % [frames / 60.0, _winner])
	var free := 0
	for y in arena.rows:
		for x in arena.cols:
			if not arena.is_solid(Vector2i(x, y)):
				free += 1
	print("INFO wolnych pól na koniec: %d" % free)
	var human: Node = null
	for p in get_nodes_in_group("players"):
		if not p.is_bot:
			human = p
	_check(human != null and not human.is_alive, "stojący człowiek zasypany")
	_check(not _last_chance, "zasypanie bez quizu ostatniej szansy")
	print("FAILED: %d" % _failed if _failed else "ALL OK")
	rm.round_time_limit = 180.0
	quit(1 if _failed else 0)
