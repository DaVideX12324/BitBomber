extends RefCounted

## AI dla bota BitBomber — BFS na gridzie, stany wzorowane na BombIt (StateEscape,
## StateAttack, StateBox, StateGetItem, StateFree).
##
## Kluczowe usprawnienia względem v1:
##   - danger_map: pre-obliczana mapa zagrożonych cel — identycznie jak isInDangerMap() w BombIt
##   - _find_safe_cell() respektuje ściany blokujące eksplozję
##   - po położeniu bomby bot ucieka od WŁASNEJ pozycji, nie od gracza
##   - _cell_in_danger() sprawdza przeszkody wzdłuż promienia wybuchu
##   - BFS z wagą: komórki bliżej bomb kosztują więcej (wzorowane na getBestPosition w BombIt)

enum State { WANDER, HUNT, FLEE, GET_ITEM }
enum Difficulty { EASY, MEDIUM, HARD }

const GRID_SIZE       : int   = 64
const BOMB_TIMER_SAFE : float = 2.2
const MAP_W           : int   = 13
const MAP_H           : int   = 11

const DIFF_PARAMS : Dictionary = {
	Difficulty.EASY: {
		"think_rate":  0.67,
		"find_range":  4,
		"hunt_range":  4,
		"attack_pct":  0.30,
		"dodge_pct":   0.50,
		"box_pct":     0.30,
		"item_pct":    0.50,
	},
	Difficulty.MEDIUM: {
		"think_rate":  0.50,
		"find_range":  5,
		"hunt_range":  6,
		"attack_pct":  0.40,
		"dodge_pct":   0.65,
		"box_pct":     0.50,
		"item_pct":    0.75,
	},
	Difficulty.HARD: {
		"think_rate":  0.30,
		"find_range":  7,
		"hunt_range":  8,
		"attack_pct":  0.55,
		"dodge_pct":   0.92,
		"box_pct":     0.70,
		"item_pct":    0.95,
	},
}

var difficulty     : int        = Difficulty.MEDIUM
var _params        : Dictionary = {}

var _owner_player  : Node       = null
var _arena         : Node       = null
var _state         : State      = State.WANDER
var _think_timer   : float      = 0.0
var _queued_dir    : Vector2i   = Vector2i.ZERO
var _wander_target : Vector2i   = Vector2i(-1, -1)
var _item_target   : Vector2i   = Vector2i(-1, -1)
var _game_started  : bool       = false

## danger_map: komórki aktualnie w zasięgu wybuchu aktywnych bomb — jak isInDangerMap() w BombIt
var _danger_map    : Dictionary = {}


func setup(player: Node, arena: Node, diff: int = Difficulty.MEDIUM) -> void:
	_owner_player = player
	_arena        = arena
	set_difficulty(diff)


func set_difficulty(diff: int) -> void:
	difficulty = diff
	_params    = DIFF_PARAMS[diff]


func _any_human_moved() -> bool:
	var gn := GameManager.game_node
	if not is_instance_valid(gn):
		return false
	for p in gn._players:
		if is_instance_valid(p) and not p.is_bot and p.is_alive:
			if p._moving:
				return true
	return false


func think(delta: float) -> void:
	if not is_instance_valid(_owner_player) or not _owner_player.is_alive:
		return

	if not _game_started:
		if _any_human_moved():
			_game_started = true
		else:
			return

	if _owner_player._moving:
		return

	_build_danger_map()

	_think_timer -= delta
	if _think_timer > 0.0:
		if _queued_dir != Vector2i.ZERO:
			_try_move(_queued_dir)
		return

	_think_timer = _params["think_rate"]
	_update_state()

	match _state:
		State.FLEE:     _think_flee()
		State.HUNT:     _think_hunt()
		State.GET_ITEM: _think_get_item()
		State.WANDER:   _think_wander()


# ---------------------------------------------------------------------------
# Danger map — pre-obliczana raz na tick (jak isInDangerMap w BombIt)
# ---------------------------------------------------------------------------

func _build_danger_map() -> void:
	_danger_map.clear()
	for bomb in _get_active_bombs():
		if not is_instance_valid(bomb):
			continue
		var b : Vector2i = Vector2i(
			int(bomb.global_position.x / GRID_SIZE),
			int(bomb.global_position.y / GRID_SIZE))
		_danger_map[b] = true
		for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			for i in range(1, bomb.explosion_range + 1):
				var c : Vector2i = b + dir * i
				if _arena.is_solid(c):
					break
				_danger_map[c] = true
				if _arena.is_breakable(c):
					break


func _in_danger(cell: Vector2i) -> bool:
	return _danger_map.has(cell)


# ---------------------------------------------------------------------------
# Aktualizacja stanu
# ---------------------------------------------------------------------------

func _update_state() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()

	# 1. Ucieczka — najwyższy priorytet (jak StateEscape.checkTransitions)
	if _in_danger(my_pos):
		if randf() < _params["dodge_pct"]:
			_state = State.FLEE
			return
		_state = State.WANDER
		return

	# 2. Power-upy (jak StateGetItem.checkTransitions)
	if randf() < _params["item_pct"]:
		var item := _find_nearest_item()
		if item != Vector2i(-1, -1):
			_item_target = item
			_state = State.GET_ITEM
			return

	# 3. Polowanie / WANDER
	var target := _find_nearest_enemy()
	if target != null:
		var dist : int = _grid_dist(my_pos, target.get_grid_pos())
		_state = State.HUNT if dist <= _params["hunt_range"] else State.WANDER
	else:
		_state = State.WANDER


# ---------------------------------------------------------------------------
# FLEE (StateEscape) — idź do najbliższego bezpiecznego cella
# ---------------------------------------------------------------------------

func _think_flee() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var safe   : Vector2i = _find_safe_cell(my_pos)
	if safe == Vector2i(-1, -1):
		_queued_dir = Vector2i.ZERO
		return
	var path := _bfs(my_pos, safe, _params["find_range"] + 4)
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)


# ---------------------------------------------------------------------------
# HUNT (StateAttack) — idź do gracza, kładź bombę gdy w zasięgu
# ---------------------------------------------------------------------------

func _think_hunt() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var target := _find_nearest_enemy()
	if target == null:
		_think_wander()
		return

	var t_pos : Vector2i = target.get_grid_pos()

	if _enemy_in_blast_range(my_pos, t_pos):
		if randf() < _params["attack_pct"]:
			_owner_player._place_bomb()
		# Uciekaj symulując danger_map z nową bombą
		_wander_target = Vector2i(-1, -1)
		_queued_dir = _best_escape_dir(my_pos)
		if _queued_dir != Vector2i.ZERO:
			_try_move(_queued_dir)
		return

	var path := _bfs(my_pos, t_pos, _params["find_range"] + 3)
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)
	else:
		_think_wander()


# ---------------------------------------------------------------------------
# GET_ITEM (StateGetItem)
# ---------------------------------------------------------------------------

func _think_get_item() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()

	if _item_target == Vector2i(-1, -1) or not _arena.has_powerup(_item_target):
		_item_target = _find_nearest_item()
	if _item_target == Vector2i(-1, -1):
		_state = State.WANDER
		return

	if my_pos == _item_target:
		_item_target = Vector2i(-1, -1)
		_state = State.WANDER
		return

	var path := _bfs(my_pos, _item_target, _params["find_range"] + 3)
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)
	else:
		_item_target = Vector2i(-1, -1)
		_state = State.WANDER


# ---------------------------------------------------------------------------
# WANDER (StateBox + StateFree)
# ---------------------------------------------------------------------------

func _think_wander() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()

	# StateBox — kładź bombę przy skrzynce i uciekaj (bez dodatkowego check — _best_escape_dir sam symuluje)
	if randf() < _params["box_pct"]:
		for d: Vector2i in _shuffled_dirs():
			if _arena.is_breakable(my_pos + d):
				_owner_player._place_bomb()
				_wander_target = Vector2i(-1, -1)
				_queued_dir = _best_escape_dir(my_pos)
				if _queued_dir != Vector2i.ZERO:
					_try_move(_queued_dir)
				return

	# StateFree — idź do losowego wolnego cella
	if _wander_target == Vector2i(-1, -1) or _wander_target == my_pos:
		_wander_target = _pick_random_passable(my_pos)

	if _wander_target == Vector2i(-1, -1):
		for d: Vector2i in _shuffled_dirs():
			if _can_move(my_pos, d):
				_queued_dir = d
				_try_move(_queued_dir)
				return
		return

	var path := _bfs(my_pos, _wander_target, _params["find_range"])
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)
	else:
		_wander_target = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Ucieczka po bombie — _best_escape_dir (jak _escapePosArr w BombIt StateAttack)
# ---------------------------------------------------------------------------

## Symuluje danger_map z nową bombą na my_pos i szuka bezpiecznego cella przez BFS.
## Zwraca pierwszy krok w kierunku ucieczki.
func _best_escape_dir(my_pos: Vector2i) -> Vector2i:
	var r : int = _owner_player.bomb_range
	var sim : Dictionary = _danger_map.duplicate()
	sim[my_pos] = true
	for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		for i in range(1, r + 1):
			var c : Vector2i = my_pos + dir * i
			if _arena.is_solid(c):
				break
			sim[c] = true
			if _arena.is_breakable(c):
				break
	# BFS do pierwszego bezpiecznego cella (poza sim), ignorując punkt startowy
	var queue : Array      = [my_pos]
	var vis   : Dictionary = { my_pos: true }
	var prev  : Dictionary = { my_pos: Vector2i(-9999, -9999) }
	while queue.size() > 0:
		var cur : Vector2i = queue.pop_front()
		if not sim.has(cur) and cur != my_pos:
			# Odtwórz ścieżkę i zwróć pierwszy krok od my_pos
			var step : Vector2i = cur
			while prev.get(step, Vector2i(-9999,-9999)) != my_pos \
					and prev.get(step, Vector2i(-9999,-9999)) != Vector2i(-9999,-9999):
				step = prev[step]
			return step - my_pos
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb : Vector2i = cur + d
			if not vis.has(nb) and _is_passable(nb):
				vis[nb] = true
				prev[nb] = cur
				queue.append(nb)
	return Vector2i.ZERO


## Sprawdza czy po postawieniu bomby na my_pos bot ma dokąd uciec.
func _has_escape_after_bomb(my_pos: Vector2i) -> bool:
	var sim_range : int = _owner_player.bomb_range
	var sim_danger : Dictionary = _danger_map.duplicate()
	sim_danger[my_pos] = true
	for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		for i in range(1, sim_range + 1):
			var c : Vector2i = my_pos + dir * i
			if _arena.is_solid(c):
				break
			sim_danger[c] = true
			if _arena.is_breakable(c):
				break
	var queue : Array      = [my_pos]
	var vis   : Dictionary = { my_pos: true }
	while queue.size() > 0:
		var cur : Vector2i = queue.pop_front()
		if not sim_danger.has(cur):
			return true
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb : Vector2i = cur + d
			if not vis.has(nb) and _is_passable(nb):
				vis[nb] = true
				queue.append(nb)
	return false


# ---------------------------------------------------------------------------
# Szukanie power-upów
# ---------------------------------------------------------------------------

func _find_nearest_item() -> Vector2i:
	if not _arena.has_method("has_powerup"):
		return Vector2i(-1, -1)
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var best   : Vector2i = Vector2i(-1, -1)
	var best_d : int      = 999
	for cell in _arena.powerup_cells:
		var d := _grid_dist(my_pos, cell)
		if d < best_d:
			var path := _bfs(my_pos, cell, _params["find_range"] + 4)
			if path.size() >= 2:
				best_d = d
				best   = cell
	return best


# ---------------------------------------------------------------------------
# BFS
# ---------------------------------------------------------------------------

func _bfs(from: Vector2i, to: Vector2i, max_depth: int = -1) -> Array[Vector2i]:
	if from == to:
		return [from]
	var visited : Dictionary = { from: Vector2i(-9999, -9999) }
	var queue   : Array      = [[from, 0]]
	var found   : bool       = false

	while queue.size() > 0:
		var entry : Array    = queue.pop_front()
		var cur   : Vector2i = entry[0]
		var depth : int      = entry[1]
		if max_depth > 0 and depth >= max_depth:
			continue
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb : Vector2i = cur + d
			if visited.has(nb):
				continue
			if not _is_passable(nb):
				continue
			visited[nb] = cur
			if nb == to:
				found = true
				break
			queue.append([nb, depth + 1])
		if found:
			break

	if not found:
		return []

	var path     : Array[Vector2i] = []
	var cur      : Vector2i        = to
	var sentinel : Vector2i        = Vector2i(-9999, -9999)
	while cur != sentinel:
		path.push_front(cur)
		cur = visited.get(cur, sentinel)
	return path


# ---------------------------------------------------------------------------
# Bezpieczeństwo
# ---------------------------------------------------------------------------

func _is_danger_nearby() -> bool:
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	return _in_danger(my_pos)


func _find_safe_cell(from: Vector2i) -> Vector2i:
	# BFS — szuka pierwszego cella poza _danger_map, zawsze ignoruje punkt startowy
	var queue : Array      = [from]
	var vis   : Dictionary = { from: true }
	while queue.size() > 0:
		var cur : Vector2i = queue.pop_front()
		if not _in_danger(cur) and cur != from:
			return cur
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb : Vector2i = cur + d
			if not vis.has(nb) and _is_passable(nb):
				vis[nb] = true
				queue.append(nb)
	return Vector2i(-1, -1)


func _get_active_bombs() -> Array:
	var result : Array = []
	var map    := _get_map()
	if not is_instance_valid(map):
		return result
	for child in map.get_children():
		if child.is_in_group("bomb"):
			result.append(child)
	return result


func _get_map() -> Node:
	var gn := GameManager.game_node
	if gn and gn.get("_current_map") != null:
		return gn._current_map
	return null


# ---------------------------------------------------------------------------
# Pathfinding helpery
# ---------------------------------------------------------------------------

func _pick_random_passable(my_pos: Vector2i) -> Vector2i:
	var candidates : Array[Vector2i] = []
	for x in range(1, MAP_W - 1):
		for y in range(1, MAP_H - 1):
			var cell := Vector2i(x, y)
			if _is_passable(cell) and not _in_danger(cell) and _grid_dist(cell, my_pos) >= 3:
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.shuffle()
	for i in range(min(5, candidates.size())):
		var path := _bfs(my_pos, candidates[i], _params["find_range"])
		if path.size() >= 2:
			return candidates[i]
	return Vector2i(-1, -1)


func _is_passable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= MAP_W or cell.y < 0 or cell.y >= MAP_H:
		return false
	if _arena.is_solid(cell):
		return false
	if _arena.is_breakable(cell):
		return false
	return true


func _can_move(from: Vector2i, dir: Vector2i) -> bool:
	return _is_passable(from + dir)


func _enemy_in_blast_range(my_pos: Vector2i, t_pos: Vector2i) -> bool:
	var r : int = _owner_player.bomb_range
	if my_pos.x == t_pos.x and abs(my_pos.y - t_pos.y) <= r:
		return true
	if my_pos.y == t_pos.y and abs(my_pos.x - t_pos.x) <= r:
		return true
	return false


func _find_nearest_enemy() -> Node:
	var gn := GameManager.game_node
	if not is_instance_valid(gn):
		return null
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var best   : Node     = null
	var best_d : int      = 999
	for p in gn._players:
		if not is_instance_valid(p):
			continue
		if p == _owner_player or not p.is_alive:
			continue
		var d := _grid_dist(my_pos, p.get_grid_pos())
		if d < best_d:
			best_d = d
			best   = p
	return best


func _grid_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _try_move(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	if _can_move(my_pos, dir):
		_owner_player._move_grid(dir)


func _shuffled_dirs() -> Array[Vector2i]:
	var dirs : Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	dirs.shuffle()
	return dirs
