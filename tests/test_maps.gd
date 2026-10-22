extends SceneTree

## Każda mapa z resources/maps: wczytuje się, 4 spawny na wolnych polach w obrysie z murów,
## wszystkie niestałe pola osiągalne ze spawnu (skrzynki da się wysadzić), przy spawnie miejsce na ucieczkę.
## godot --headless --path <host> -s res://modules/BitBomber/tests/test_maps.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")
const Arena = preload("../scripts/arena.gd")

var _failed := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		print("FAIL ", msg)


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.box_density = 1.0
	var ids := Arena.list_maps()
	_check(ids.size() >= 28, "liczba map %d" % ids.size())
	for id in ids:
		gm.selected_map = id
		var arena: Node2D = load(BBRuntime.path("scenes/maps/arena.tscn")).instantiate()
		root.add_child(arena)
		await process_frame
		_check(arena.map_id == id, "%s: wczytana" % id)
		_check(arena.spawn_points.size() == 4, "%s: 4 spawny" % id)
		for x in arena.cols:
			_check(arena.is_solid(Vector2i(x, 0)) and arena.is_solid(Vector2i(x, arena.rows - 1)), "%s: mur góra/dół x=%d" % [id, x])
		for y in arena.rows:
			_check(arena.is_solid(Vector2i(0, y)) and arena.is_solid(Vector2i(arena.cols - 1, y)), "%s: mur lewo/prawo y=%d" % [id, y])
		for sp: Vector2i in arena.spawn_points:
			_check(not arena.is_solid(sp) and not arena.is_breakable(sp), "%s: spawn %s wolny" % [id, sp])
			var free_nb := 0
			for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if not arena.is_solid(sp + d) and not arena.is_breakable(sp + d):
					free_nb += 1
			_check(free_nb >= 1, "%s: spawn %s ma wolnego sąsiada" % [id, sp])
		# Spójność: z pierwszego spawnu da się dojść (przez skrzynki) do każdego niestałego pola.
		var seen := {arena.spawn_points[0]: true}
		var queue: Array[Vector2i] = [arena.spawn_points[0]]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var n: Vector2i = c + d
				if not seen.has(n) and not arena.is_solid(n):
					seen[n] = true
					queue.append(n)
		var open := 0
		for y in arena.rows:
			for x in arena.cols:
				if not arena.is_solid(Vector2i(x, y)):
					open += 1
		_check(seen.size() == open, "%s: osiągalne %d / %d" % [id, seen.size(), open])
		print("%-16s %dx%d skrzynek %d" % [id, arena.cols, arena.rows, arena.breakable_cells.size()])
		arena.queue_free()
		await process_frame
	print("FAILED: %d" % _failed if _failed else "ALL OK")
	quit(1 if _failed else 0)
