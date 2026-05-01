extends RefCounted

## AI dla bota Bomberman — BFS na gridzie 13x13.
## Stany: WANDER (losowy ruch), HUNT (gonenie gracza), FLEE (ucieczka od bomby).
## Bot nie rusza się dopóki żaden gracz ludzki nie wykona pierwszego ruchu.

enum State { WANDER, HUNT, FLEE }

const GRID_SIZE       : int   = 64
const THINK_RATE      : float = 0.35
const BOMB_TIMER_SAFE : float = 1.4

var _owner_player : Node     = null
var _arena        : Node     = null
var _state        : State    = State.WANDER
var _think_timer  : float    = 0.0
var _queued_dir   : Vector2i = Vector2i.ZERO
var _wander_steps : int      = 0
var _game_started : bool     = false


func setup(player: Node, arena: Node) -> void:
	_owner_player = player
	_arena        = arena


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

	_think_timer -= delta
	if _think_timer > 0.0:
		if _queued_dir != Vector2i.ZERO:
			_try_move(_queued_dir)
		return

	_think_timer = THINK_RATE
	_update_state()

	match _state:
		State.FLEE:   _think_flee()
		State.HUNT:   _think_hunt()
		State.WANDER: _think_wander()


# ---------------------------------------------------------------------------
# Aktualizacja stanu
# ---------------------------------------------------------------------------

func _update_state() -> void:
	if _is_danger_nearby():
		_state = State.FLEE
		return
	var target := _find_nearest_human()
	if target != null:
		var my_pos : Vector2i = _owner_player.get_grid_pos()
		var t_pos  : Vector2i = target.get_grid_pos()
		var dist : int = _grid_dist(my_pos, t_pos)
		_state = State.HUNT if dist <= 6 else State.WANDER
	else:
		_state = State.WANDER


# ---------------------------------------------------------------------------
# FLEE
# ---------------------------------------------------------------------------

func _think_flee() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var safe   : Vector2i = _find_safe_cell(my_pos)
	if safe == Vector2i(-1, -1):
		_queued_dir = Vector2i.ZERO
		return
	var path := _bfs(my_pos, safe)
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)


# ---------------------------------------------------------------------------
# HUNT
# ---------------------------------------------------------------------------

func _think_hunt() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var target := _find_nearest_human()
	if target == null:
		_think_wander()
		return

	var t_pos : Vector2i = target.get_grid_pos()
	var dist  : int      = _grid_dist(my_pos, t_pos)

	if dist == 1:
		_owner_player._place_bomb()
		_queued_dir = _flee_dir_from(t_pos)
		_try_move(_queued_dir)
		return

	var path := _bfs(my_pos, t_pos)
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)
	else:
		_think_wander()


# ---------------------------------------------------------------------------
# WANDER
# ---------------------------------------------------------------------------

func _think_wander() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()

	for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		if _arena.is_breakable(my_pos + d):
			_owner_player._place_bomb()
			_queued_dir = -d
			_try_move(_queued_dir)
			return

	_wander_steps -= 1
	if _wander_steps <= 0 or not _can_move(my_pos, _queued_dir):
		var dirs := _shuffled_dirs()
		_queued_dir = Vector2i.ZERO
		for d: Vector2i in dirs:
			if _can_move(my_pos, d):
				_queued_dir   = d
				_wander_steps = randi_range(2, 5)
				break

	if _queued_dir != Vector2i.ZERO:
		_try_move(_queued_dir)


# ---------------------------------------------------------------------------
# BFS
# ---------------------------------------------------------------------------

func _bfs(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	var visited : Dictionary = { from: Vector2i(-9999, -9999) }
	var queue   : Array      = [from]
	var found   : bool       = false

	while queue.size() > 0:
		var cur : Vector2i = queue.pop_front()
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
			queue.append(nb)
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
# Bezpieczenstwo
# ---------------------------------------------------------------------------

func _is_danger_nearby() -> bool:
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	for bomb in _get_active_bombs():
		if not is_instance_valid(bomb):
			continue
		var t_left : float = bomb.time_left() if bomb.has_method("time_left") else 9.0
		if t_left > BOMB_TIMER_SAFE:
			continue
		var b_grid : Vector2i = Vector2i(
			int(bomb.global_position.x / GRID_SIZE),
			int(bomb.global_position.y / GRID_SIZE))
		var r : int = bomb.explosion_range + 1
		if b_grid.x == my_pos.x and abs(b_grid.y - my_pos.y) <= r:
			return true
		if b_grid.y == my_pos.y and abs(b_grid.x - my_pos.x) <= r:
			return true
	return false


func _find_safe_cell(from: Vector2i) -> Vector2i:
	var bombs := _get_active_bombs()
	var queue : Array      = [from]
	var vis   : Dictionary = { from: true }
	while queue.size() > 0:
		var cur : Vector2i = queue.pop_front()
		if not _cell_in_danger(cur, bombs):
			return cur
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb : Vector2i = cur + d
			if not vis.has(nb) and _is_passable(nb):
				vis[nb] = true
				queue.append(nb)
	return Vector2i(-1, -1)


func _cell_in_danger(cell: Vector2i, bombs: Array) -> bool:
	for bomb in bombs:
		if not is_instance_valid(bomb):
			continue
		var b_grid : Vector2i = Vector2i(
			int(bomb.global_position.x / GRID_SIZE),
			int(bomb.global_position.y / GRID_SIZE))
		var r : int = bomb.explosion_range + 1
		if b_grid.x == cell.x and abs(b_grid.y - cell.y) <= r:
			return true
		if b_grid.y == cell.y and abs(b_grid.x - cell.x) <= r:
			return true
	return false


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


func _flee_dir_from(threat: Vector2i) -> Vector2i:
	var my   : Vector2i = _owner_player.get_grid_pos()
	var diff : Vector2i = my - threat
	var dirs : Array[Vector2i]
	if abs(diff.x) >= abs(diff.y):
		dirs = [Vector2i(sign(diff.x), 0), Vector2i(0, sign(diff.y)),
				Vector2i(-sign(diff.x), 0), Vector2i(0, -sign(diff.y))]
	else:
		dirs = [Vector2i(0, sign(diff.y)), Vector2i(sign(diff.x), 0),
				Vector2i(0, -sign(diff.y)), Vector2i(-sign(diff.x), 0)]
	for d: Vector2i in dirs:
		if _can_move(my, d):
			return d
	return Vector2i.ZERO


# ---------------------------------------------------------------------------
# Ruch
# ---------------------------------------------------------------------------

func _try_move(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO or not is_instance_valid(_owner_player):
		return
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var target : Vector2i = my_pos + dir
	if not _is_passable(target):
		_queued_dir = Vector2i.ZERO
		return
	# Kolizja z bombą — bot może wyjść z własnej bomby (jak gracz), ale nie wejść na inną
	if _owner_player.is_bomb_blocking(target):
		_queued_dir = Vector2i.ZERO
		return
	_owner_player._grid_pos      = target
	_owner_player._move_from     = _owner_player.global_position
	_owner_player._pixel_target  = Vector2(
		target.x * GRID_SIZE + GRID_SIZE / 2,
		target.y * GRID_SIZE + GRID_SIZE / 2)
	_owner_player._move_progress = 0.0
	_owner_player._moving        = true


func _can_move(from: Vector2i, dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return false
	var target : Vector2i = from + dir
	if not _is_passable(target):
		return false
	if _owner_player.is_bomb_blocking(target):
		return false
	return true


func _is_passable(cell: Vector2i) -> bool:
	if not is_instance_valid(_arena):
		return false
	if _arena.is_solid(cell):
		return false
	if _arena.is_breakable(cell):
		return false
	return true


# ---------------------------------------------------------------------------
# Helpery
# ---------------------------------------------------------------------------

func _find_nearest_human() -> Node:
	var gn := GameManager.game_node
	if not is_instance_valid(gn):
		return null
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var best   : Node     = null
	var best_d : int      = 9999
	for p in gn._players:
		if not is_instance_valid(p):
			continue
		if p == _owner_player or p.is_bot or not p.is_alive:
			continue
		var p_pos : Vector2i = p.get_grid_pos()
		var d     : int      = _grid_dist(my_pos, p_pos)
		if d < best_d:
			best_d = d
			best   = p
	return best


func _grid_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _shuffled_dirs() -> Array[Vector2i]:
	var dirs : Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	dirs.shuffle()
	return dirs
