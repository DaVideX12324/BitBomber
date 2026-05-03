# ======================================================
# INSTRUKCJA PODPIĘCIA:
# Zastąp właściwości bota w sekcji "BOT NODE INTERFACE"
# jeśli twoje zmienne mają inne nazwy niż domyślne.
# ======================================================

extends Node
class_name BombItAI

# ------ BOT NODE INTERFACE -------------------------
# Zmień na właściwy typ jeśli nie używasz CharacterBody2D
@export var bot_node: CharacterBody2D

# Rozmiar kratki siatki w pikselach (powinien zgadzać się z mapą)
@export var grid_size: int = 64

# Wymiary siatki planszy
@export var grid_width: int = 15
@export var grid_height: int = 13

# Poziom trudności
enum Difficulty { EASY = 0, MEDIUM = 1, HARD = 2 }
@export var difficulty: Difficulty = Difficulty.MEDIUM

# === NAZWY WŁAŚCIWOŚCI NA BOT_NODE ===
# Kierunek ruchu bota (ustaw do Vector2 przez AI)
const BOT_DIR_PROP       = "bot_input_direction"
# Czy bot chce teraz kłaść bombę (ustaw na true, gracz sam czyści)
const BOT_BOMB_PROP      = "bot_wants_to_bomb"
# Ile bomb teraz aktywnych
const BOT_ACTIVE_BOMBS   = "_active_bombs"
# Maks bomb jakie może mieć naraz
const BOT_MAX_BOMBS      = "max_bombs"
# Zasięg wybuchu jego bomby
const BOT_BOMB_RANGE     = "bomb_range"
# Czy żywy
const BOT_IS_ALIVE       = "is_alive"
# Czy zablokowany (zamrożony itp.)
const BOT_FROZEN         = "_frozen"

# === GRUPY SCENY ===
const GROUP_BOMB     = "bomb"      # węzły bomb
const GROUP_POWERUP  = "powerup"   # węzły power-upów
const GROUP_PLAYER   = "players"   # wszyscy gracze (bot + ludzcy)

# === NODE ARENY ===
# Arena musi mieć metody:
#   is_solid(cell: Vector2i) -> bool         (ściana niezniszczalna)
#   is_breakable(cell: Vector2i) -> bool     (skrzynka do zniszczenia)
# lub możesz ustawić zmienną arena ręcznie z zewnątrz.
var arena: Node = null

# ---------------------------------------------------

# =====================
# TIMING (aiAnswerTime z BombIt7)
# =====================
const ANSWER_TIME: Array[float] = [0.55, 0.22, 0.08]

# =====================
# ZASIĘG PERCEPCJI (findRange z BombIt7)
# =====================
const FIND_RANGE: Array[int] = [4, 6, 99]

# =====================
# STATE SETTINGS — wzorowane na StateSettings/XML z BombIt7
# =====================
class StateSettings:
	var percentage:     float = 0.8
	var bomb_chance:    float = 0.9
	var dodge_on_step:  float = 1.0
	var attack_on_step: float = 0.0
	var noise_chance:   float = 0.0

func _make_settings(state_name: String) -> StateSettings:
	var s := StateSettings.new()
	match difficulty:
		Difficulty.EASY:
			match state_name:
				"escape":
					s.percentage = 1.0;  s.dodge_on_step = 0.5
				"box":
					s.percentage = 0.6;  s.bomb_chance = 0.4
					s.dodge_on_step = 0.3; s.noise_chance = 0.35
				"get_item":
					s.percentage = 0.0   # EASY nie szuka powerupów
				"attack":
					s.percentage = 0.10   # EASY rzadko atakuje celowo
				"idle":
					s.percentage = 0.80  # EASY często stoi

		Difficulty.MEDIUM:
			match state_name:
				"escape":
					s.percentage = 1.0;  s.dodge_on_step = 1.0
				"box":
					s.percentage = 0.75; s.bomb_chance = 0.75; s.dodge_on_step = 0.8
				"get_item":
					s.percentage = 0.70
				"attack":
					s.percentage = 0.40; s.attack_on_step = 0.0
				"idle":
					s.percentage = 0.50

		Difficulty.HARD:
			match state_name:
				"escape":
					s.percentage = 1.0;  s.dodge_on_step = 1.0
				"box":
					s.percentage = 0.90; s.bomb_chance = 1.0
					s.dodge_on_step = 1.0; s.attack_on_step = 0.4
				"get_item":
					s.percentage = 0.85
				"attack":
					s.percentage = 0.75; s.attack_on_step = 0.5
				"idle":
					s.percentage = 0.15  # HARD prawie nigdy nie stoi
	return s

# =====================
# FSM STATES
# =====================
enum BotState { IDLE, ESCAPE, ATTACK, BOX, GET_ITEM }

var current_state: BotState = BotState.IDLE
var _action_complete: bool = true
var _state_repeat: int = 0

var _settings: Dictionary = {}

var _last_pos: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0

var danger_map: Dictionary = {}
var astar_grid: AStarGrid2D
var current_path: Array[Vector2i] = []

var ai_think_timer: float = 0.0
var ai_answer_time: float = 0.22

# =====================
# INIT
# =====================
func _ready():
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.get("bot_difficulty") != null:
		difficulty = gm.bot_difficulty as Difficulty
	ai_answer_time = ANSWER_TIME[int(difficulty)]
	arena = _find_arena()
	_init_astar()
	_settings[BotState.IDLE]     = _make_settings("idle")
	_settings[BotState.ESCAPE]   = _make_settings("escape")
	_settings[BotState.BOX]      = _make_settings("box")
	_settings[BotState.GET_ITEM] = _make_settings("get_item")
	_settings[BotState.ATTACK]   = _make_settings("attack")
	_dbg("=== AI gotowy [%s] ===" % Difficulty.keys()[int(difficulty)])

func _dbg(msg: String):
	var alive = "LIVING"
	if bot_node and bot_node.get(BOT_IS_ALIVE) == false:
		alive = "DEAD"
	var state_str = BotState.keys()[current_state] if current_state != null else "NONE"
	print("[BotAI | %s | %s] %s" % [alive, state_str, msg])

func _find_arena() -> Node:
	var arenas = get_tree().get_nodes_in_group("arena")
	if arenas.size() > 0:
		return arenas[0]
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.get("game_node") and is_instance_valid(gm.game_node):
		var gn = gm.game_node
		if gn.get("_current_map") and is_instance_valid(gn._current_map):
			return gn._current_map
	return bot_node.get_parent() if bot_node else null

# =====================
# PHYSICS PROCESS
# =====================
func _physics_process(delta: float):
	if not is_instance_valid(bot_node):
		return
	if not bot_node.get(BOT_IS_ALIVE):
		bot_node.set(BOT_DIR_PROP, Vector2.ZERO)
		return
	if bot_node.get(BOT_FROZEN) == true:
		bot_node.set(BOT_DIR_PROP, Vector2.ZERO)
		return

	ai_think_timer += delta
	if ai_think_timer >= ai_answer_time:
		ai_think_timer = 0.0
		_update_sense()
		_machine_update()

	# Dodaliśmy podawanie 'delta' do poruszania się
	_execute_move(delta)

# =====================
# A* GRID
# =====================
func _init_astar():
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, grid_width, grid_height)
	astar_grid.cell_size = Vector2(grid_size, grid_size)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()
	
func _refresh_astar():
	if not arena: return
	for x in range(grid_width):
		for y in range(grid_height):
			var cell := Vector2i(x, y)
			var solid := false
			if arena.has_method("is_solid") and arena.is_solid(cell):
				solid = true
			elif arena.has_method("is_breakable") and arena.is_breakable(cell):
				solid = true
			astar_grid.set_point_solid(cell, solid)

# =====================
# DANGER MAP
# =====================
func _update_sense():
	danger_map.clear()
	_refresh_astar()
	
	for bomb in get_tree().get_nodes_in_group(GROUP_BOMB):
		var brange = int(bomb.get("explosion_range")) if bomb.get("explosion_range") != null else 2
		_mark_danger(_cell(bomb.global_position), brange)
	
	for exp in get_tree().get_nodes_in_group("explosion"):
		var e_cell = _cell(exp.global_position)
		danger_map[e_cell] = true
		
	# _dbg("Zaktualizowano danger_map. Zablokowanych kratek (niebezpieczeństwo): %d" % danger_map.size())
		
func _mark_danger(bpos: Vector2i, power: int):
	danger_map[bpos] = true
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		for i in range(1, power):
			var cp : Vector2i = bpos + dir * i
			if _out_of_bounds(cp):
				break
			if arena and arena.has_method("is_solid") and arena.is_solid(cp):
				break
			danger_map[cp] = true
			if arena and arena.has_method("is_breakable") and arena.is_breakable(cp):
				break

# =====================
# FSM
# =====================
func _machine_update():
	if not _action_complete:
		_on_step()
		return

	var next := _check_transitions()

	if next != current_state:
		_dbg("TRANSITION: %s -> %s" % [BotState.keys()[current_state], BotState.keys()[next]])
		_exit_state(current_state)
		current_state = next
		_state_repeat = 0
		_enter_state(current_state)
	else:
		_state_repeat += 1
		if _state_repeat >= 5:
			_dbg("!!! UTKNĄŁEM !!! stateRepeat >= 5. Reset do IDLE.")
			_state_repeat = 0
			if current_state != BotState.IDLE:
				_exit_state(current_state)
				current_state = BotState.IDLE
				_enter_state(BotState.IDLE)
			return

	_update_state(current_state)

func _check_transitions() -> BotState:
	if _check_escape():   return BotState.ESCAPE
	if _check_attack():   return BotState.ATTACK
	if _check_get_item(): return BotState.GET_ITEM
	if _check_box():      return BotState.BOX
	return BotState.IDLE

func _check_escape() -> bool:
	var s: StateSettings = _settings[BotState.ESCAPE]
	if randf() > s.percentage: return false
	return _bot_in_danger()

func _check_attack() -> bool:
	var s: StateSettings = _settings[BotState.ATTACK]
	if randf() > s.percentage: return false
	if _active_bombs() >= _max_bombs(): return false
	var pos := _cell(bot_node.global_position)
	if _nearest_enemy(pos) == Vector2i(-1, -1): return false
	return _plant_bomb_possible(pos)

func _check_get_item() -> bool:
	var s: StateSettings = _settings[BotState.GET_ITEM]
	if randf() > s.percentage: return false
	if get_tree().get_nodes_in_group(GROUP_POWERUP).is_empty(): return false
	return _nearest_item(_cell(bot_node.global_position)) != Vector2i(-1, -1)

func _check_box() -> bool:
	var s: StateSettings = _settings[BotState.BOX]
	if randf() > s.percentage: return false
	if _active_bombs() >= _max_bombs(): return false
	if not arena or not arena.has_method("is_breakable"): return false
	var pos := _cell(bot_node.global_position)
	var box := _nearest_box(pos)
	if box == Vector2i(-1, -1): return false
	return float((box - pos).length()) <= float(FIND_RANGE[int(difficulty)])

# =====================
# enter / exit / update
# =====================
func _enter_state(state: BotState):
	var pos := _cell(bot_node.global_position)
	_dbg("ENTER_STATE: %s z pozycji %s" % [BotState.keys()[state], pos])
	
	current_path.clear()
	_action_complete = false
	
	match state:
		BotState.IDLE:
			_action_complete = true
			_dbg("Odpoczywam (IDLE).")
		BotState.ESCAPE:
			var safe := _best_escape(pos)
			_dbg("Ucieczka! Szukam bezpiecznego punktu: %s" % safe)
			_try_set_path(pos, safe)
		BotState.ATTACK:
			var enemy := _nearest_enemy(pos)
			if enemy != Vector2i(-1, -1):
				var apos := _find_attack_pos(enemy, pos)
				_dbg("Atakuję! Przeciwnik na %s, idę na pozycję ataku: %s" % [enemy, apos])
				_try_set_path(pos, apos)
			else:
				_dbg("Nie znaleziono przeciwnika do ataku.")
				_action_complete = true
		BotState.BOX:
			var box := _nearest_box(pos)
			_dbg("Znalazłem skrzynkę na %s, ruszam." % box)
			_try_set_path(pos, box)
		BotState.GET_ITEM:
			var item := _nearest_item(pos)
			_dbg("Widzę powerup na %s, ruszam po niego." % item)
			_try_set_path(pos, item)

func _try_set_path(from: Vector2i, to: Vector2i):
	if to == Vector2i(-1, -1) or to == from:
		_dbg("Anulowano szukanie ścieżki: cel to -1/-1 lub tożsamy z obecną pozycją.")
		_action_complete = true
		return
	
	astar_grid.set_point_solid(from, false)
	var path := astar_grid.get_id_path(from, to)
	
	if path.size() > 0:
		if path[0] == from: 
			path.remove_at(0)
		
		if path.size() > 0 and _path_safe(path):
			current_path = path
			_dbg("Ścieżka ustalona pomyślnie. Długość w kratkach: %d" % current_path.size())
		else:
			_dbg("Ścieżka znaleziona, ale uznana za NIEBEZPIECZNĄ. Zatrzymuję akcję.")
			_action_complete = true
	else:
		_dbg("AStar nie znalazł ścieżki z %s do %s." % [from, to])
		_action_complete = true

func _exit_state(state: BotState):
	_dbg("EXIT_STATE: %s" % BotState.keys()[state])
	bot_node.set(BOT_DIR_PROP, Vector2.ZERO)

func _update_state(state: BotState):
	if _action_complete and current_path.is_empty():
		_dbg("Re-evaluate stanu (actionComplete == true).")
		_enter_state(state)

# =====================
# onStep
# =====================
func _on_step():
	var s: StateSettings = _settings[current_state]

	# stepDodge: bot omija przeszkody, JEŚLI nie jest w trybie ESCAPE
	if current_state != BotState.ESCAPE and randf() < s.dodge_on_step and _next_cell_in_danger():
		_dbg("stepDodge! Następna kratka jest zagrożona. Zatrzymuję ruch i czyszczę ścieżkę.")
		current_path.clear()
		_action_complete = true
		return

	if difficulty == Difficulty.HARD and randf() < s.attack_on_step:
		if current_state in [BotState.BOX, BotState.ATTACK]:
			var pos := _cell(bot_node.global_position)
			var enemy := _nearest_enemy(pos)
			if enemy != Vector2i(-1, -1) and _can_hit(pos, enemy) and _plant_bomb_possible(pos):
				_dbg("stepAttack: Kładę bombę 'w biegu'!")
				bot_node.set(BOT_BOMB_PROP, true)
				_mark_danger(pos, _bomb_range())
				current_path.clear()
				_action_complete = true
				
# =====================
# EXECUTE MOVE
# =====================
func _execute_move(delta: float):
	if current_path.is_empty():
		bot_node.set(BOT_DIR_PROP, Vector2.ZERO)
		return

	# 1. WYKRYWANIE FIZYCZNEGO ZABLOKOWANIA (Anti-Stuck)
	# Jeśli bot przesunął się o mniej niż 1 piksel kwadratowy od ostatniej klatki...
	if bot_node.global_position.distance_squared_to(_last_pos) < 1.0:
		_stuck_timer += delta
		if _stuck_timer > 0.3: # ...przez 0.3 sekundy, to znaczy, że uderzył w ścianę!
			_dbg("Zahaczyłem o ścianę! Resetuję ścieżkę.")
			current_path.clear()
			_action_complete = true
			_stuck_timer = 0.0
			return
	else:
		_stuck_timer = 0.0 # Bot się rusza normalnie, zerujemy licznik
	
	_last_pos = bot_node.global_position

	# 2. POBIERANIE CELU
	var next_cell := current_path[0]
	var target_px := Vector2(
		next_cell.x * grid_size + grid_size * 0.5,
		next_cell.y * grid_size + grid_size * 0.5
	)
	var diff := target_px - bot_node.global_position

	# 3. PŁYNNE PRZECHODZENIE (Bez zatrzymywania na środku kratki!)
	# Margines akceptacji celu ustawiony na 6 pikseli
	if abs(diff.x) <= 6.0 and abs(diff.y) <= 6.0:
		current_path.pop_front()
		
		if current_path.is_empty():
			# To była ostatnia kratka, tutaj faktycznie się zatrzymujemy
			bot_node.set(BOT_DIR_PROP, Vector2.ZERO)
			_on_path_complete()
			return
		else:
			# Wciąż mamy trasę! Bierzemy OD RAZU następny cel, bez zerowania ruchu.
			next_cell = current_path[0]
			target_px = Vector2(
				next_cell.x * grid_size + grid_size * 0.5,
				next_cell.y * grid_size + grid_size * 0.5
			)
			diff = target_px - bot_node.global_position

	# 4. USTALANIE KIERUNKU (Priorytet dla osi z większym dystansem)
	var dir := Vector2.ZERO
	
	if abs(diff.x) > abs(diff.y):
		dir.x = sign(diff.x)
	else:
		dir.y = sign(diff.y)

	bot_node.set(BOT_DIR_PROP, dir)

func _on_path_complete():
	var pos := _cell(bot_node.global_position)
	_dbg("Koniec ścieżki osiągnięty na kratce %s." % pos)

	match current_state:
		BotState.BOX, BotState.ATTACK:
			if _active_bombs() < _max_bombs() and _plant_bomb_possible(pos):
				_dbg("Cel osiągnięty (BOX/ATTACK) - podkładam bombę na %s!" % pos)
				bot_node.set(BOT_BOMB_PROP, true)
				_update_sense() 
				_exit_state(current_state)
				current_state = BotState.ESCAPE
				_enter_state(BotState.ESCAPE)
				return 
			else:
				_dbg("Nie mogę położyć bomby: max bomb osiągnięty lub brak drogi ucieczki.")
	_action_complete = true

# =====================
# BFS / HELPERS (pozostają logiką bez zmian by zachować przejrzystość logów)
# =====================
func _plant_bomb_possible(pos: Vector2i) -> bool:
	var sim := danger_map.duplicate()
	var power := _bomb_range()
	sim[pos] = true
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		for i in range(1, power + 1):
			var cp : Vector2i = pos + dir * i
			if _out_of_bounds(cp): break
			if arena and arena.has_method("is_solid") and arena.is_solid(cp): break
			sim[cp] = true
			if arena and arena.has_method("is_breakable") and arena.is_breakable(cp): break

	var queue := [pos]
	var visited := {pos: true}
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if not sim.has(cur) and not astar_grid.is_point_solid(cur):
			return true
		for d in dirs:
			var nb : Vector2i = cur + d
			if _out_of_bounds(nb): continue
			if visited.has(nb): continue
			if astar_grid.is_point_solid(nb): continue
			visited[nb] = true
			queue.push_back(nb)
	return false

func _best_escape(start: Vector2i) -> Vector2i:
	if not danger_map.has(start):
		return start
	var queue := [start]
	var visited := {start: true}
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if not danger_map.has(cur) and not astar_grid.is_point_solid(cur):
			var path = astar_grid.get_id_path(start, cur)
			if path.size() > 0:
				return cur
		for d in dirs:
			var nb : Vector2i = cur + d
			if _out_of_bounds(nb): continue
			if visited.has(nb): continue
			if astar_grid.is_point_solid(nb): continue
			visited[nb] = true
			queue.push_back(nb)
	return Vector2i(-1, -1)

func _nearest_box(start: Vector2i) -> Vector2i:
	if not arena or not arena.has_method("is_breakable"):
		return Vector2i(-1, -1)
	var queue := [start]
	var visited := {start: true}
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var rlimit := float(FIND_RANGE[int(difficulty)])
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if float((cur - start).length()) > rlimit: continue
		if not danger_map.has(cur):
			for d in dirs:
				var nb : Vector2i = cur + d
				if arena.is_breakable(nb): return cur
		for d in dirs:
			var nb : Vector2i = cur + d
			if _out_of_bounds(nb): continue
			if visited.has(nb): continue
			if not astar_grid.is_point_solid(nb):
				visited[nb] = true
				queue.push_back(nb)
	return Vector2i(-1, -1)

func _nearest_item(start: Vector2i) -> Vector2i:
	var cells: Dictionary = {}
	for p in get_tree().get_nodes_in_group(GROUP_POWERUP):
		cells[_cell(p.global_position)] = true
	if cells.is_empty(): return Vector2i(-1, -1)
	var queue := [start]
	var visited := {start: true}
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cells.has(cur) and not danger_map.has(cur): return cur
		for d in dirs:
			var nb : Vector2i = cur + d
			if _out_of_bounds(nb): continue
			if visited.has(nb): continue
			if not astar_grid.is_point_solid(nb):
				visited[nb] = true
				queue.push_back(nb)
	return Vector2i(-1, -1)

func _nearest_enemy(start: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999999.0
	var rlimit := float(FIND_RANGE[int(difficulty)])
	for p in get_tree().get_nodes_in_group(GROUP_PLAYER):
		if p == bot_node: continue
		if "is_alive" in p and not p.is_alive: continue
		var ep := _cell(p.global_position)
		var d := float((ep - start).length())
		if d < best_d and d <= rlimit:
			best_d = d; best = ep
	return best

func _find_attack_pos(enemy: Vector2i, bot_pos: Vector2i) -> Vector2i:
	var brange := _bomb_range()
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		for i in range(1, brange + 1):
			var cand : Vector2i = enemy + dir * i
			if _out_of_bounds(cand) or astar_grid.is_point_solid(cand): break
			if danger_map.has(cand): continue
			if _can_hit(cand, enemy):
				var path := astar_grid.get_id_path(bot_pos, cand)
				if path.size() > 0 and _path_safe(path):
					return cand
	return Vector2i(-1, -1)

func _can_hit(from: Vector2i, target: Vector2i) -> bool:
	var brange := _bomb_range()
	if from.x == target.x:
		var dy: int = int(sign(target.y - from.y))
		if dy == 0: return true
		for i in range(1, brange + 1):
			var cp := from + Vector2i(0, dy * i)
			if arena and arena.has_method("is_solid") and arena.is_solid(cp): return false
			if cp == target: return true
	elif from.y == target.y:
		var dx: int = int(sign(target.x - from.x))
		if dx == 0: return true
		for i in range(1, brange + 1):
			var cp := from + Vector2i(dx * i, 0)
			if arena and arena.has_method("is_solid") and arena.is_solid(cp): return false
			if cp == target: return true
	return false

func _path_safe(path: Array[Vector2i]) -> bool:
	if current_state == BotState.ESCAPE: 
		return true 
		
	for cell in path:
		if danger_map.has(cell): 
			return false
	return true

func _next_cell_in_danger() -> bool:
	if current_path.is_empty(): return false
	return danger_map.has(current_path[0])

func _bot_in_danger() -> bool:
	var center := bot_node.global_position
	for cell: Vector2i in danger_map:
		var cc := Vector2(cell.x * grid_size + grid_size * 0.5,
						  cell.y * grid_size + grid_size * 0.5)
		if center.distance_to(cc) < float(grid_size) * 0.9:
			return true
	return false

func _random_free_dir(pos: Vector2i) -> Vector2:
	var opts := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
	opts.shuffle()
	for d in opts:
		var nb := pos + Vector2i(int(d.x), int(d.y))
		if not _out_of_bounds(nb) and not astar_grid.is_point_solid(nb) and not danger_map.has(nb):
			return d
	return Vector2.ZERO

# =====================
# UTIL
# =====================
func _cell(gpos: Vector2) -> Vector2i:
	return Vector2i(int(gpos.x / float(grid_size)), int(gpos.y / float(grid_size)))

func _out_of_bounds(c: Vector2i) -> bool:
	return c.x < 0 or c.y < 0 or c.x >= grid_width or c.y >= grid_height

func _active_bombs() -> int:
	return int(bot_node.get(BOT_ACTIVE_BOMBS)) if bot_node.get(BOT_ACTIVE_BOMBS) != null else 0

func _max_bombs() -> int:
	return int(bot_node.get(BOT_MAX_BOMBS)) if bot_node.get(BOT_MAX_BOMBS) != null else 1

func _bomb_range() -> int:
	return int(bot_node.get(BOT_BOMB_RANGE)) if bot_node.get(BOT_BOMB_RANGE) != null else 2
