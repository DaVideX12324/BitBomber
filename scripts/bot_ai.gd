extends Node
class_name BombItAI

@export var grid_size: int = 64
@export var bot_node: CharacterBody2D

# 1:1 Odwzorowanie stanów z AIEngine.as
enum State { IDLE, ESCAPE, ATTACK, BOX, GET_ITEM }
var current_state: State = State.IDLE

var danger_map: Dictionary = {}
var astar_grid: AStarGrid2D
var current_path: Array[Vector2i] = []

var ai_think_timer: float = 0.0
# W Bomb It 7 (AIControl.as) aiAnswerTime determinuje czas reakcji.
var ai_answer_time: float = 0.15 

var arena: Node
var _last_logged_state: State = State.IDLE

func _ready():
	arena = _find_arena()
	_init_astar()
	_log("Zainicjalizowano AI bota (Logika Bomb It 7).")

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
		
	# Zabezpieczenie przed uwięzieniem logiki gdy gracz dostaje hit (odpowiednik isStun/isTrapped)
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
		if b_pos != bot_pos: # Bot może stać na bombie dopóki z niej nie zejdzie
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
	var next_state = check_transitions()
	
	# Zmieniamy stan, jeśli AIEngine tak zdecyduje, ALBO jeśli skończyliśmy iść (pusta ścieżka)
	if next_state != current_state or current_path.is_empty():
		if next_state != _last_logged_state:
			_log("FSM: %s -> %s" % [State.keys()[current_state], State.keys()[next_state]])
			_last_logged_state = next_state
			
		current_state = next_state
		enter_state(current_state)

func check_transitions() -> State:
	var bot_pos = _get_grid_pos(bot_node.global_position)
	
	# 1. StateEscape.as: Sprawdzamy dangerMap
	if danger_map.has(bot_pos):
		return State.ESCAPE
		
	# 2. Jeśli mamy bomby, przechodzimy do ataku/skrzynek
	if bot_node._active_bombs < bot_node.max_bombs:
		if _has_items_nearby() and _find_nearest_item(bot_pos) != Vector2i(-1, -1):
			return State.GET_ITEM
		if _has_boxes_nearby() and _find_nearest_destroyable_box(bot_pos) != Vector2i(-1, -1):
			return State.BOX
			
	# 3. W przeciwnym wypadku StateIdle
	return State.IDLE

func enter_state(new_state: State):
	current_path.clear()
	var bot_pos = _get_grid_pos(bot_node.global_position)
	bot_node.bot_input_direction = Vector2.ZERO
	
	match new_state:
		State.ESCAPE:
			var safe_node = _find_best_escape_position(bot_pos)
			if safe_node != Vector2i(-1, -1) and safe_node != bot_pos:
				current_path = astar_grid.get_id_path(bot_pos, safe_node)
				
		State.BOX:
			var target_box = _find_nearest_destroyable_box(bot_pos)
			if target_box != Vector2i(-1, -1):
				var path = astar_grid.get_id_path(bot_pos, target_box)
				if _is_path_safe(path):
					current_path = path
				else:
					current_state = State.IDLE 
					
		State.GET_ITEM:
			var target_item = _find_nearest_item(bot_pos)
			if target_item != Vector2i(-1, -1):
				var path = astar_grid.get_id_path(bot_pos, target_item)
				if _is_path_safe(path):
					current_path = path
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
	var target_global_pos = Vector2(next_node.x * grid_size + grid_size / 2.0, next_node.y * grid_size + grid_size / 2.0)
	var current_pos = bot_node.global_position
	
	var diff = target_global_pos - current_pos
	
	# 1:1 Odwzorowanie logiki Action.as - naciskamy tylko JEDEN przycisk na raz!
	if abs(diff.x) > 2.0:
		bot_node.bot_input_direction = Vector2(sign(diff.x), 0)
	elif abs(diff.y) > 2.0:
		bot_node.bot_input_direction = Vector2(0, sign(diff.y))
	else:
		# Dotarliśmy idealnie do środka kratki!
		bot_node.bot_input_direction = Vector2.ZERO
		current_path.pop_front()
		
		# Jeśli to był cel ostateczny...
		if current_path.is_empty():
			if current_state == State.BOX:
				_log("Cel osiągnięty. Zrzucam bombę!")
				bot_node.bot_wants_to_bomb = true
				
				# StateAttack.as / StateBox.as - ucieczka od własnej bomby
				var bomb_pos = _get_grid_pos(bot_node.global_position)
				_mark_danger(bomb_pos, bot_node.bomb_range)
				
				current_state = State.ESCAPE
				enter_state(State.ESCAPE)

# ==========================================
# ALGORYTMY Z BOMB IT (getBestPosition / RoadSearch)
# ==========================================
func _is_path_safe(path: Array[Vector2i]) -> bool:
	for node in path:
		if danger_map.has(node):
			return false
	return true

# Odwzorowanie funkcji getBestPosition() ze StateEscape.as
func _find_best_escape_position(start_pos: Vector2i) -> Vector2i:
	if not danger_map.has(start_pos):
		return start_pos # Jesteśmy bezpieczni, stój w miejscu
		
	var best_node = Vector2i(-1, -1)
	var min_cost = 9999
	
	# Wylewamy się (BFS) po mapie szukając wszystkich bezpiecznych pól
	var queue = [start_pos]
	var visited = {start_pos: true}
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	while not queue.is_empty():
		var current = queue.pop_front()
		
		# Znalazłem bezpieczne pole! Oceniam jego dystans.
		if not danger_map.has(current) and not astar_grid.is_point_solid(current):
			var path = astar_grid.get_id_path(start_pos, current)
			if path.size() > 0 and path.size() < min_cost:
				min_cost = path.size()
				best_node = current
				# W Bomb It przeszukuje dalej dla optymalizacji, ale pierwszy BFS jest zazwyczaj najkrótszy
				return best_node 
				
		for dir in dirs:
			var neighbor = current + dir
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= astar_grid.region.size.x or neighbor.y >= astar_grid.region.size.y:
				continue
			if not visited.has(neighbor) and not astar_grid.is_point_solid(neighbor):
				visited[neighbor] = true
				queue.push_back(neighbor)
				
	return best_node

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
				# Jeśli obok PUSTEGO, BEZPIECZNEGO pola jest skrzynka, idziemy tam!
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
	if powerups.is_empty(): return Vector2i(-1, -1)
	
	var best_node = Vector2i(-1, -1)
	var min_dist = 9999
	
	for p in powerups:
		var p_pos = _get_grid_pos(p.global_position)
		if not astar_grid.is_point_solid(p_pos) and not danger_map.has(p_pos):
			var path = astar_grid.get_id_path(start_pos, p_pos)
			if not path.is_empty() and path.size() < min_dist:
				min_dist = path.size()
				best_node = p_pos
				
	return best_node

func _has_boxes_nearby() -> bool:
	if not arena: return false
	return arena.breakable_cells.size() > 0

func _has_items_nearby() -> bool:
	return get_tree().get_nodes_in_group("powerup").size() > 0

func _get_grid_pos(global_pos: Vector2) -> Vector2i:
	return Vector2i(int(global_pos.x / grid_size), int(global_pos.y / grid_size))
