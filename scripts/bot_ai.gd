extends RefCounted

## AI dla bota Bomberman — BFS na gridzie 13x13.
## Stany: WANDER (losowy cel BFS), HUNT (gon­ienie gracza), FLEE (ucieczka od bomby).
## Bot nie rusza się dopóki żaden gracz ludzki nie wykona pierwszego ruchu.
## Poziomy trudności wzorowane na wartościach z Bomb It 7 (AIControl XML config).

enum State { WANDER, HUNT, FLEE }

enum Difficulty { EASY, MEDIUM, HARD }

const GRID_SIZE       : int   = 64
const BOMB_TIMER_SAFE : float = 1.4
const MAP_W           : int   = 13
const MAP_H           : int   = 11

# ---- Tabela parametrów według poziomu (wzorowana na BombIt7 XML) ----
# aiAnswerTime easy=40, medium=30, hard=20  → przeliczone na sekundy /60
# findRange    easy=4,  medium=5,  hard=7
# hunt_range   easy=4,  medium=6,  hard=8   (ile pól by wejść w tryb HUNT)
# attack_pct   easy=0.3,medium=0.4,hard=0.5 (szansa na atak w danej turze)
# dodge_pct    easy=0.5,medium=0.6,hard=0.9 (szansa na próbę ucieczki)
# box_pct      easy=0.3,medium=0.5,hard=0.7 (szansa na podejście do skrzynki)
const DIFF_PARAMS : Dictionary = {
	Difficulty.EASY: {
		"think_rate":    0.67,   # ~40/60 s
		"find_range":    4,
		"hunt_range":    4,
		"attack_pct":    0.30,
		"dodge_pct":     0.50,
		"box_pct":       0.30,
		"move_speed_mul": 1.0,
	},
	Difficulty.MEDIUM: {
		"think_rate":    0.50,   # ~30/60 s
		"find_range":    5,
		"hunt_range":    6,
		"attack_pct":    0.40,
		"dodge_pct":     0.60,
		"box_pct":       0.50,
		"move_speed_mul": 1.0,
	},
	Difficulty.HARD: {
		"think_rate":    0.33,   # ~20/60 s
		"find_range":    7,
		"hunt_range":    8,
		"attack_pct":    0.50,
		"dodge_pct":     0.90,
		"box_pct":       0.70,
		"move_speed_mul": 1.0,
	},
}

var difficulty     : int     = Difficulty.MEDIUM
var _params        : Dictionary = {}

var _owner_player  : Node     = null
var _arena         : Node     = null
var _state         : State    = State.WANDER
var _think_timer   : float    = 0.0
var _queued_dir    : Vector2i = Vector2i.ZERO
var _wander_target : Vector2i = Vector2i(-1, -1)
var _game_started  : bool     = false


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

	_think_timer -= delta
	if _think_timer > 0.0:
		if _queued_dir != Vector2i.ZERO:
			_try_move(_queued_dir)
		return

	_think_timer = _params["think_rate"]
	_update_state()

	match _state:
		State.FLEE:   _think_flee()
		State.HUNT:   _think_hunt()
		State.WANDER: _think_wander()


# ---------------------------------------------------------------------------
# Aktualizacja stanu
# ---------------------------------------------------------------------------

func _update_state() -> void:
	# FLEE — ucieczka, losowość zależy od dodge_pct
	if _is_danger_nearby():
		if randf() < _params["dodge_pct"]:
			_state = State.FLEE
			return
		# Easy/medium może zignorować niebezpieczeństwo
		_state = State.WANDER
		return

	var target := _find_nearest_enemy()
	if target != null:
		var my_pos : Vector2i = _owner_player.get_grid_pos()
		var t_pos  : Vector2i = target.get_grid_pos()
		var dist   : int      = _grid_dist(my_pos, t_pos)
		if dist <= _params["hunt_range"]:
			_state = State.HUNT
		else:
			_state = State.WANDER
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
	var path := _bfs(my_pos, safe, _params["find_range"] + 4)
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)


# ---------------------------------------------------------------------------
# HUNT
# ---------------------------------------------------------------------------

func _think_hunt() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()
	var target := _find_nearest_enemy()
	if target == null:
		_think_wander()
		return

	var t_pos : Vector2i = target.get_grid_pos()

	if _enemy_in_blast_range(my_pos, t_pos):
		# Hard atakuje prawie zawsze, Easy/Medium może odpuścić
		if randf() < _params["attack_pct"]:
			_owner_player._place_bomb()
		_wander_target = Vector2i(-1, -1)
		_queued_dir = _flee_dir_from(t_pos)
		if _queued_dir != Vector2i.ZERO:
			_try_move(_queued_dir)
		return

	var path := _bfs(my_pos, t_pos, _params["find_range"] + 3)
	if path.size() >= 2:
		_queued_dir = path[1] - path[0]
		_try_move(_queued_dir)
	else:
		_think_wander()


func _enemy_in_blast_range(my_pos: Vector2i, t_pos: Vector2i) -> bool:
	var r : int = _owner_player.bomb_range
	if my_pos.x == t_pos.x and abs(my_pos.y - t_pos.y) <= r:
		return true
	if my_pos.y == t_pos.y and abs(my_pos.x - t_pos.x) <= r:
		return true
	return false


# ---------------------------------------------------------------------------
# WANDER — losowy cel BFS + bomby przy skrzynkach
# ---------------------------------------------------------------------------

func _think_wander() -> void:
	var my_pos : Vector2i = _owner_player.get_grid_pos()

	# Postaw bombę przy skrzynce tylko z pewnym prawdopodobieństwem (box_pct)
	if randf() < _params["box_pct"]:
		for d: Vector2i in _shuffled_dirs():
			if _arena.is_breakable(my_pos + d):
				_owner_player._place_bomb()
				_queued_dir    = -d
				_wander_target = Vector2i(-1, -1)
				_try_move(_queued_dir)
				return

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


func _pick_random_passable(my_pos: Vector2i) -> Vector2i:
	var candidates : Array[Vector2i] = []
	for x in range(1, MAP_W - 1):
		for y in range(1, MAP_H - 1):
			var cell := Vector2i(x, y)
			if _is_passable(cell) and _grid_dist(cell, my_pos) >= 3:
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.shuffle()
	for i in range(min(10, candidates.size())):
		var path := _bfs(my_pos, candidates[i], _params["find_range"])
		if path.size() >= 2:
			return candidates[i]
	return Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# BFS — opcjonalny limit głębokości (max_depth = -1 oznacza brak limitu)
# ---------------------------------------------------------------------------

func _bfs(from: Vector2i, to: Vector2i, max_depth: int = -1) -> Array[Vector2i]:
	if from == to:
		return [from]
	var visited : Dictionary = { from: Vector2i(-9999, -9999) }
	var queue   : Array      = [[from, 0]]
	var found   : bool       = false

	while queue.size() > 0:
		var entry  : Array  = queue.pop_front()
		var cur    : Vector2i = entry[0]
		var depth  : int      = entry[1]
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
	var target : Vector2i = from + dir
	return _is_passable(target) and not _owner_player.is_bomb_blocking(target)


func _is_passable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= MAP_W or cell.y < 0 or cell.y >= MAP_H:
		return false
	return _arena.is_passable(cell)


func _find_nearest_enemy() -> Node:
	var gn := GameManager.game_node
	if not is_instance_valid(gn):
		return null
	var my_pos  : Vector2i = _owner_player.get_grid_pos()
	var best    : Node     = null
	var best_d  : int      = 99999
	for p in gn._players:
		if not is_instance_valid(p) or p == _owner_player or not p.is_alive:
			continue
		var d : int = _grid_dist(my_pos, p.get_grid_pos())
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
