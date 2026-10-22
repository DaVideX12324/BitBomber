extends SceneTree

## Zasięg wybuchu: arena.blast_cells + prawdziwa bomba na arenie.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_blast.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _failed := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		_failed += 1
		print("FAIL ", msg)


func _run() -> void:
	var arena: Node2D = load(BBRuntime.path("scenes/maps/arena.tscn")).instantiate()
	root.add_child(arena)
	await process_frame

	# Róg (1,1) jest zawsze spawnem: skrzynki dopiero 3 pola dalej.
	var c := Vector2i(1, 1)
	_check(arena.blast_cells(c, 0) == [c], "zasięg 0 = tylko środek")
	var b1: Array[Vector2i] = arena.blast_cells(c, 1)
	_check(b1.size() == 3 and b1.has(Vector2i(2, 1)) and b1.has(Vector2i(1, 2)), "zasięg 1 = 1 pole w każdą stronę (ściany obcinają)")
	var b5: Array[Vector2i] = arena.blast_cells(c, 5)
	_check(arena.is_breakable(Vector2i(4, 1)), "skrzynka na (4,1)")
	_check(b5.has(Vector2i(4, 1)) and not b5.has(Vector2i(5, 1)), "ogień zajmuje skrzynkę i staje")
	_check(not b5.has(Vector2i(0, 1)), "ogień nie wchodzi w ścianę")

	var bomb: Node2D = load(BBRuntime.path("scenes/objects/bomb.tscn")).instantiate()
	bomb.explosion_range = 3
	bomb.position = Vector2(c) * 64 + Vector2(32, 32)
	arena.add_child(bomb)
	for i in 200:
		await physics_frame
		if not is_instance_valid(bomb):
			break
	_check(not is_instance_valid(bomb), "bomba wybuchła")
	_check(not arena.is_breakable(Vector2i(4, 1)), "skrzynka w zasięgu 3 zniszczona")
	_check(arena.is_breakable(Vector2i(1, 4)) == false, "skrzynka (1,4) też zniszczona")

	print("FAILED: %d" % _failed if _failed else "ALL OK")
	quit(1 if _failed else 0)
