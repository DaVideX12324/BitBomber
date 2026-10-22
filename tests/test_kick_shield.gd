extends SceneTree

## Kopanie bomb, tarcza, gwiazdka (nieśmiertelność). Mapa bez skrzynek, 2 ludzi bez botów.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_kick_shield.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _failed := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		_failed += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _bomb_at(cell: Vector2i, owner: Node, fuse_delay: float = 0.0) -> Node2D:
	var bomb: Node2D = load(BBRuntime.path("scenes/objects/bomb.tscn")).instantiate()
	bomb.explosion_range = 1
	bomb.owner_player = owner
	bomb.position = Vector2(cell) * 64 + Vector2(32, 32)
	root.get_node("GameManager").game_node._current_map.add_child(bomb)
	bomb._timer = -fuse_delay
	return bomb


func _run() -> void:
	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	gm.selected_map = "forest_1"
	gm.box_density = 0.0
	gm.start_game(2, 0)
	await _frames(10)
	var p1: Node = null
	for p in get_nodes_in_group("players"):
		if p.player_id == 1:
			p1 = p
	var arena: Node = gm.game_node._current_map

	# Kopanie: P1 na (1,5) w lewej kolumnie Lasu ('b' bez skrzynek), bomba pod nim (1,6), P1 idzie w dół.
	p1.teleport_to(Vector2(1, 5) * 64 + Vector2(32, 32))
	p1.has_kick = true
	await _frames(2)
	var bomb := _bomb_at(Vector2i(1, 6), p1, 30.0)
	Input.action_press("p1_down")
	await _frames(20)
	Input.action_release("p1_down")
	await _frames(60)
	var cell: Vector2i = bomb.get_cell()
	_check(cell.x == 1 and cell.y > 6, "kopnięta bomba pojechała w dół: %s" % cell)
	_check(not bomb.is_sliding(), "bomba stanęła")
	var blocker: bool = arena.is_solid(cell + Vector2i.DOWN)
	for p in get_nodes_in_group("players"):
		if p.is_alive and p.get_grid_pos() == cell + Vector2i.DOWN:
			blocker = true   # drugi gracz na spawnie (spawny są losowe)
	_check(blocker, "stanęła przed przeszkodą (%s)" % (cell + Vector2i.DOWN))
	bomb.queue_free()

	# Bez kopania bomba stoi.
	p1.has_kick = false
	p1.teleport_to(Vector2(1, 5) * 64 + Vector2(32, 32))
	await _frames(2)
	var bomb2 := _bomb_at(Vector2i(1, 6), p1, 30.0)
	Input.action_press("p1_down")
	await _frames(30)
	Input.action_release("p1_down")
	_check(bomb2.get_cell() == Vector2i(1, 6), "bez kopania bomba stoi")
	bomb2.queue_free()
	await _frames(2)

	# Tarcza: wybuch pod graczem zjada tarczę, gracz żyje.
	p1.has_shield = true
	_bomb_at(p1.get_grid_pos(), p1)
	await _frames(150)
	_check(p1.is_alive and not p1.has_shield, "tarcza zjedzona, gracz żyje")
	await _frames(90)

	# Gwiazdka: nieśmiertelność.
	p1.apply_powerup("star")
	_bomb_at(p1.get_grid_pos(), p1)
	await _frames(150)
	_check(p1.is_alive, "gwiazdka chroni przed wybuchem")
	await _frames(int(p1.STAR_DURATION * 60))
	_check(p1._star_time == 0.0 and p1.modulate == Color.WHITE, "gwiazdka mija")

	print("FAILED: %d" % _failed if _failed else "ALL OK")
	quit(1 if _failed else 0)
