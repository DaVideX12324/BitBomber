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


func _bomb_at(arena: Node, cell: Vector2i, power: int) -> Node2D:
	var bomb: Node2D = load(BBRuntime.path("scenes/objects/bomb.tscn")).instantiate()
	bomb.explosion_range = power
	bomb.position = Vector2(cell) * 64 + Vector2(32, 32)
	arena.add_child(bomb)
	return bomb


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.selected_map = "classic"
	gm.box_density = 1.0
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

	# Reakcja łańcuchowa: B (lont na długo) w zasięgu A wybucha razem z A.
	var a := _bomb_at(arena, Vector2i(1, 1), 2)
	var b := _bomb_at(arena, Vector2i(2, 1), 1)
	b._timer = -100.0
	for i in 200:
		await physics_frame
		if not is_instance_valid(a):
			break
	for i in 5:
		await physics_frame
	_check(not is_instance_valid(b), "reakcja łańcuchowa: B odpalona ogniem A")

	# Bomba położona w płonący ogień też wybucha.
	while not get_nodes_in_group("explosion").is_empty():
		await physics_frame
	var c2 := _bomb_at(arena, Vector2i(1, 1), 1)
	c2.detonate()
	for i in 10:
		await physics_frame
	_check(not get_nodes_in_group("explosion").is_empty(), "ogień C jeszcze płonie po 10 klatkach")
	var d := _bomb_at(arena, Vector2i(1, 2), 1)
	d._timer = -100.0
	for i in 3:
		await physics_frame
	_check(not is_instance_valid(d), "bomba położona w płonący ogień wybucha")

	print("FAILED: %d" % _failed if _failed else "ALL OK")
	quit(1 if _failed else 0)
