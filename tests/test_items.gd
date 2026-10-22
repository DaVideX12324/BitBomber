extends SceneTree

## Przedmioty: wagi losowania typów, dorzucanie na mapę po 45 s co 15 s (max 12 na mapie).
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_items.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _failed := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		_failed += 1


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.selected_map = "forest_1"
	var arena: Node2D = load(BBRuntime.path("scenes/maps/arena.tscn")).instantiate()
	root.add_child(arena)
	await process_frame

	var counts := {}
	for i in 10000:
		var t: String = arena._roll_powerup_type()
		counts[t] = counts.get(t, 0) + 1
	var total := 0
	for t in arena.POWERUP_WEIGHTS:
		total += arena.POWERUP_WEIGHTS[t]
	for t in arena.POWERUP_WEIGHTS:
		var want: float = 10000.0 * arena.POWERUP_WEIGHTS[t] / total
		_check(absf(counts.get(t, 0) - want) < want * 0.15 + 30, "%s: %d (≈%d)" % [t, counts.get(t, 0), want])

	_check(arena.powerup_cells.is_empty(), "na starcie bez przedmiotów")
	arena._round_time = 44.9
	for i in 12:
		await process_frame
	_check(arena.powerup_cells.size() == 2, "po 45 s: 2 przedmioty (%d)" % arena.powerup_cells.size())
	arena._round_time = 59.9
	for i in 12:
		await process_frame
	_check(arena.powerup_cells.size() == 4, "po 60 s: 4 (%d)" % arena.powerup_cells.size())
	for t in [75, 90, 105, 120, 135, 150]:
		arena._round_time = t - 0.1
		for i in 12:
			await process_frame
	_check(arena.powerup_cells.size() == 12, "limit 12 na mapie (%d)" % arena.powerup_cells.size())
	for c in arena.powerup_cells:
		_check(not arena.is_solid(c) and not arena.is_breakable(c), "przedmiot %s na wolnym polu" % c)

	print("FAILED: %d" % _failed if _failed else "ALL OK")
	quit(1 if _failed else 0)
