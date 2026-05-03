extends Node
class_name BombItAI

@export var grid_size: int = 64
@export var bot_node: CharacterBody2D

# ==========================================
# 3 POZIOMY TRUDNOŚCI
# ==========================================
enum Difficulty { EASY = 0, MEDIUM = 1, HARD = 2 }

## Ustaw przed add_child() lub przez @export w edytorze.
@export var difficulty: Difficulty = Difficulty.MEDIUM

## Czas reakcji (sekundy) — im niższy, tym szybszy bot.
const ANSWER_TIME : Array[float] = [0.5, 0.2, 0.08]

## Zasięg szukania (ile kratek od bota) — Easy widzi mniej.
const FIND_RANGE  : Array[int]   = [3, 5, 99]

## Szansa (0–1) na złożenie bomby przy skrzynce/wrogu:
## Easy czasem odpuszcza, Hard zawsze kładzie.
const BOMB_CHANCE : Array[float] = [0.4, 0.7, 1.0]

## Easy ignoruje power-upy (nie biegnie po nie).
const CHASE_ITEMS : Array[bool]  = [false, true, true]

# 1:1 Odwzorowanie stanów z AIEngine.as
enum State { IDLE, ESCAPE, ATTACK, BOX, GET_ITEM }
var current_state: State = State.IDLE

var danger_map: Dictionary = {}
var astar_grid: AStarGrid2D
var current_path: Array[Vector2i] = []

var ai_think_timer: float = 0.0
var ai_answer_time : float = 0.2  # nadpisywane w _ready() wg difficulty

var arena: Node
var _last_logged_state: State = State.IDLE

## Flaga: bot jest w trakcie wykonywania ścieżki — nie przerywaj stanu
var _executing_action: bool = false

func _ready():
	# Wczytaj parametry odpowiednie dla poziomu trudności
	ai_answer_time = ANSWER_TIME[difficulty]
	arena = _find_arena()
	_init_astar()
	_log("Zainicjalizowano AI bota [%s] (Logika Bomb It 7)." % Difficulty.keys()[difficulty])

func _log(msg: String):
	var pid = bot_node.player_id if bot_node and "player_id" in bot_node else "?"
	print("[BotAI P%s] %s" % [str(pid), msg])

func _find_arena() -> Node:
	var gn = get_node_or_null("/root/GameManager").game_node
	if gn and is_instance_valid(gn.get("_current_map")):
		return gn._current_map
	return null

func _physics_process(delta: float):
	if not is_instance_valid(bot_node) or not bot_node.is_alive:
		return

	if bot_node.get("_frozen") == true:
		bot_node.bot_input_direction = Vector2.ZERO
		return

	ai_think_timer += delta
	if ai_think_timer >= ai_answer_time:
		ai_think_timer = 0.0
		update_sense()
		machine_update()

	execute_move()

# ==========================================
# SYSTEM A* I MAPA ZAGROŻEŃ (RoadSearch.as & AIControl.as)
# ==========================================
func _init_astar():
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, 50, 50)
	astar_grid.cell_size = Vector2(grid_size, grid_size)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()
	_update_astar_obstacles()

func _update_astar_obstacles():
	if not arena: return

	for x in range(astar_grid.region.size.x):
		for y in range(astar_grid.region.size.y):
			var cell = Vector2i(x, y)
			var is_solid = false

			if arena.has_method("is_solid") and arena.is_solid(cell):
				is_solid = true
			elif arena.has_method("is_breakable") and arena.is_breakable(cell):
				is_solid = true

			astar_grid.set_point_solid(cell, is_solid)

	var bot_pos = _get_grid_pos(bot_node.global_position)
	for bomb in get_tree().get_nodes_in_group("bomb"):
		var b_pos = _get_grid_pos(bomb.global_position)
		if b_pos != bot_pos:
			astar_grid.set_point_solid(b_pos, true)

func update_sense():
	danger_map.clear()
	_update_astar_obstacles()

	var bombs = get_tree().get_nodes_in_group("bomb")
	for bomb in bombs:
		var bomb_pos = _get_grid_pos(bomb.global_position)
		var power = bomb.explosion_range if "explosion_range" in bomb else 2
		_mark_danger(bomb_pos, power)

func _mark_danger(bomb_pos: Vector2i, power: int):
	danger_map[bomb_pos] = true
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for dir in dirs:
		for i in range(1, power + 1):
			var check_pos = bomb_pos + (dir * i)

			if arena and arena.has_method("is_solid") and arena.is_solid(check_pos):
				break

			danger_map[check_pos] = true

			if arena and arena.has_method("is_breakable") and arena.is_breakable(check_pos):
				break

# ==========================================
# MASZYNA STANÓW (AIEngine.as)
# ==========================================
func machine_update():
	# Jeśli bot jest w trakcie wykonywania ścieżki — nie przerywaj stanu,
	# chyba że wpadł w niebezpieczeństwo (ESCAPE ma zawsze priorytet)
	if _executing_action:
		if _is_bot_in_danger():
			_executing_action = false
			current_path.clear()
			current_state = State.ESCAPE
			enter_state(State.ESCAPE)
		return

	var next_state = check_transitions()

	if next_state != current_state or current_path.is_empty():
		if next_state != _last_logged_state:
			_log("FSM: %s -> %s" % [State.keys()[current_state], State.keys()[next_state]])
			_last_logged_state = next_state

		current_state = next_state
		enter_state(current_state)

func check_transitions() -> State:
	var bot_pos = _get_grid_pos(bot_node.global_position)

	# 1. Ucieczka — zawsze priorytet na każdym poziomie
	if _is_bot_in_danger():
		return State.ESCAPE

	if bot_node._active_bombs < bot_node.max_bombs:
		# Power-upy — Easy ich ignoruje
		if CHASE_ITEMS[difficulty] and _has_items_nearby():
			var item_pos = _find_nearest_item(bot_pos)
			if item_pos != Vector2i(-1, -1):
				# Na FIND_RANGE sprawdzamy czy item jest wystarczająco blisko
				var dist = (item_pos - bot_pos).length()
				if dist <= FIND_RANGE[difficulty]:
					return State.GET_ITEM

		# Skrzynki — Easy/Medium/Hard różnią się zasięgiem szukania
		if _has_boxes_nearby():
			var box_pos = _find_nearest_destroyable_box(bot_pos)
			if box_pos != Vector2i(-1, -1):
				var dist = (box_pos - bot_pos).length()
				if dist <= FIND_RANGE[difficulty]:
					return State.BOX

	return State.IDLE

func enter_state(new_state: State):
	current_path.clear()
	_executing_action = false
	var bot_pos = _get_grid_pos(bot_node.global_position)
	bot_node.bot_input_direction = Vector2.ZERO

	match new_state:
		State.ESCAPE:
			var safe_node = _find_best_escape_position(bot_pos)
			if safe_node != Vector2i(-1, -1) and safe_node != bot_pos:
				current_path = astar_grid.get_id_path(bot_pos, safe_node)
				_executing_action = true

		State.BOX:
			var target_box = _find_nearest_destroyable_box(bot_pos)
			if target_box != Vector2i(-1, -1):
				var path = astar_grid.get_id_path(bot_pos, target_box)
				if _is_path_safe(path):
					current_path = path
					_executing_action = true
				else:
					current_state = State.IDLE

		State.GET_ITEM:
			var target_item = _find_nearest_item(bot_pos)
			if target_item != Vector2i(-1, -1):
				var path = astar_grid.get_id_path(bot_pos, target_item)
				if _is_path_safe(path):
					current_path = path
					_executing_action = true
				else:
					current_state = State.IDLE

# ==========================================
# KONTROLER RUCHU (Action.as)
# ==========================================
func execute_move():
	if current_path.is_empty():
		bot_node.bot_input_direction = Vector2.ZERO
		return

	var next_node = current_path[0]
	var target_global_pos = Vector2(
		next_node.x * grid_size + grid_size / 2.0,
		next_node.y * grid_size + grid_size / 2.0
	)
	var diff = target_global_pos - bot_node.global_position

	if abs(diff.x) > 4.0:
		bot_node.bot_input_direction = Vector2(sign(diff.x), 0)
	elif abs(diff.y) > 4.0:
		bot_node.bot_input_direction = Vector2(0, sign(diff.y))
	else:
		# Snapnij dokładnie do środka kratki
		bot_node.global_position = target_global_pos
		bot_node.bot_input_direction = Vector2.ZERO
		current_path.pop_front()

		if current_path.is_empty():
			_executing_action = false
			if current_state == State.BOX:
				# BOMB_CHANCE: Easy czasem nie kładzie bomby
				if randf() <= BOMB_CHANCE[difficulty]:
					_log("Zrzucam bombę! [%s]" % Difficulty.keys()[difficulty])
					bot_node.bot_wants_to_bomb = true

					var bomb_pos = _get_grid_pos(bot_node.global_position)
					_mark_danger(bomb_pos, bot_node.bomb_range)

					current_state = State.ESCAPE
					enter_state(State.ESCAPE)
				else:
					# Easy zrezygnował z położenia bomby, wróć do IDLE
					current_state = State.IDLE
					enter_state(State.IDLE)

# ==========================================
# ALGORYTMY PATHFINDING
# ==========================================
func _is_path_safe(path: Array[Vector2i]) -> bool:
	for node in path:
		if danger_map.has(node):
			return false
	return true

func _find_best_escape_position(start_pos: Vector2i) -> Vector2i:
	if not danger_map.has(start_pos):
		return start_pos

	var queue = [start_pos]
	var visited = {start_pos: true}
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while not queue.is_empty():
		var current = queue.pop_front()

		if not danger_map.has(current) and not astar_grid.is_point_solid(current):
			var path = astar_grid.get_id_path(start_pos, current)
			if path.size() > 0:
				return current

		for dir in dirs:
			var neighbor = current + dir
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= astar_grid.region.size.x or neighbor.y >= astar_grid.region.size.y:
				continue
			if not visited.has(neighbor) and not astar_grid.is_point_solid(neighbor):
				visited[neighbor] = true
				queue.push_back(neighbor)

	return Vector2i(-1, -1)

func _find_nearest_destroyable_box(start_pos: Vector2i) -> Vector2i:
	if not arena or not arena.has_method("is_breakable"):
		return Vector2i(-1, -1)

	var queue = [start_pos]
	var visited = {start_pos: true}
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while not queue.is_empty():
		var current = queue.pop_front()

		if not danger_map.has(current):
			for dir in dirs:
				var neighbor = current + dir
				if arena.is_breakable(neighbor):
					return current

		for dir in dirs:
			var neighbor = current + dir
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= astar_grid.region.size.x or neighbor.y >= astar_grid.region.size.y:
				continue
			if not visited.has(neighbor) and not astar_grid.is_point_solid(neighbor):
				visited[neighbor] = true
				queue.push_back(neighbor)

	return Vector2i(-1, -1)

func _find_nearest_item(start_pos: Vector2i) -> Vector2i:
	var powerups = get_tree().get_nodes_in_group("powerup")
	if powerups.is_empty():
		return Vector2i(-1, -1)

	# Zbierz pozycje wszystkich powerupów
	var pu_cells: Dictionary = {}
	for p in powerups:
		pu_cells[_get_grid_pos(p.global_position)] = true

	# BFS — szukamy kratki z której można wejść na powerup
	# (czyli samej kratki powerupa, bo jest przejezdna)
	var queue = [start_pos]
	var visited = {start_pos: true}
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while not queue.is_empty():
		var current = queue.pop_front()

		if pu_cells.has(current) and not danger_map.has(current):
			return current

		for dir in dirs:
			var neighbor = current + dir
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= astar_grid.region.size.x or neighbor.y >= astar_grid.region.size.y:
				continue
			if not visited.has(neighbor) and not astar_grid.is_point_solid(neighbor):
				visited[neighbor] = true
				queue.push_back(neighbor)

	return Vector2i(-1, -1)

	
func _is_bot_in_danger() -> bool:
	var center := bot_node.global_position
	for cell in danger_map:
		var cell_center := Vector2(
			cell.x * grid_size + grid_size * 0.5,
			cell.y * grid_size + grid_size * 0.5
		)
		if center.distance_to(cell_center) < 60.0:
			return true
	return false
	
func _has_boxes_nearby() -> bool:
	if not arena: return false
	return arena.breakable_cells.size() > 0

func _has_items_nearby() -> bool:
	return get_tree().get_nodes_in_group("powerup").size() > 0

func _get_grid_pos(global_pos: Vector2) -> Vector2i:
	return Vector2i(int(global_pos.x / grid_size), int(global_pos.y / grid_size))
