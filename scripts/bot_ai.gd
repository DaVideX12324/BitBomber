# ======================================================
# INSTRUKCJA PODPIĘCIA:
# Zastąp właściwości bota w sekcji "BOT NODE INTERFACE"
# jeśli twoje zmienne mają inne nazwy niż domyślne.
# ======================================================

extends Node
class_name BotAi

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
# PROFILE (resources/ai/bot_profiles.json — liczby z GameAI Bomb It 7)
# =====================
const BBRuntime = preload("bb_runtime.gd")
const PROFILES_PATH := "resources/ai/bot_profiles.json"
## Bomb It StateIdle: stoi tyle sekund (przerywa, gdy pole robi się groźne)
const IDLE_TIME : float = 0.5
## Koszt przejścia przez pole w zasięgu bomby przy wyznaczaniu trasy (zwykłe pole = 1)
const DANGER_PATH_WEIGHT : float = 20.0
## Czas do wybuchu świeżo położonej bomby (bomb.gd FUSE_TIME)
const BOMB_FUSE : float = 2.0
## Pola nagłej śmierci: blok spadnie zaraz (8 pól ostrzeżenia co 0,2 s)
const SUDDEN_DEATH_DANGER_TIME : float = 0.4
## Odchylenie od środka pola (px), od którego bot najpierw się wyrównuje, zanim skręci
const ALIGN_TOLERANCE : float = 6.0
## Zapas czasu przy ucieczce: pole musi zostać opuszczone tyle sekund przed ogniem
const ESCAPE_MARGIN : float = 0.25

## Jeden wpis listy stanów profilu: stan + szansa przy sprawdzeniu + szanse uniku / bomby w biegu na krok.
class StateEntry:
	var state: int
	var chance: float = 1.0
	var dodge: float = 0.4
	var attack: float = 0.2

static var _profiles: Dictionary = {}

var find_range: int = 5
var _entries: Array[StateEntry] = []
var _default_entry: StateEntry
## Wpis, który uruchomił bieżący stan (jego dodge / attack działają na każdym kroku)
var _cur_entry: StateEntry
var _idle_left: float = 0.0


static func _load_profiles() -> Dictionary:
	if _profiles.is_empty():
		var path := BBRuntime.path(PROFILES_PATH)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if parsed is Dictionary:
			_profiles = parsed
		else:
			push_error("BotAI: brak albo błędny %s" % path)
	return _profiles


func _apply_profile() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var mode := "kill" if gm and gm.is_kill_mode() else "last_standing"
	var list: Array = _load_profiles().get(mode, [])
	if list.is_empty():
		_default_entry = _make_entry({"state": "free"})
		return
	var prof: Dictionary = list[clampi(int(difficulty), 0, list.size() - 1)]
	ai_answer_time = float(prof.get("answer_time", 0.04))
	find_range = int(prof.get("find_range", 5))
	for e in prof.get("states", []):
		_entries.append(_make_entry(e))
	_default_entry = _make_entry(prof.get("default", {"state": "free"}))
	if is_instance_valid(bot_node):
		bot_node.set("move_speed_scale", float(prof.get("move_speed", 1.0)))
		var start_range := int(prof.get("bomb_range", 1))
		if int(bot_node.get(BOT_BOMB_RANGE)) < start_range:
			bot_node.set(BOT_BOMB_RANGE, start_range)


func _make_entry(d: Dictionary) -> StateEntry:
	var e := StateEntry.new()
	e.state = BotState.get(str(d.get("state", "free")).to_upper(), BotState.FREE)
	e.chance = float(d.get("chance", 1.0))
	e.dodge = float(d.get("dodge", 0.4))
	e.attack = float(d.get("attack", 0.2))
	return e

# =====================
# FSM STATES
# =====================
enum BotState { IDLE, ESCAPE, ATTACK, BOX, GET_ITEM, FREE }

var current_state: BotState = BotState.IDLE
var _action_complete: bool = true
var _state_repeat: int = 0


var _last_pos: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0

var danger_map: Dictionary = {}
var astar_grid: AStarGrid2D
var current_path: Array[Vector2i] = []

var ai_think_timer: float = 0.0
var ai_answer_time: float = 0.04

# =====================
# INIT
# =====================
func _ready():
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.get("bot_difficulty") != null:
		difficulty = gm.bot_difficulty as Difficulty
		
	randomize()
	arena = _find_arena()
	# FETCH DIMENSIONS FROM ARENA
	if arena != null:
		if "cols" in arena:
			grid_width = arena.cols
		if "rows" in arena:
			grid_height = arena.rows
		# Also update grid size if it exists in arena to ensure perfect sync
		if "GRID_SIZE" in arena:
			grid_size = arena.GRID_SIZE
			
	_init_astar()
	_apply_profile()
	_cur_entry = _default_entry
	# Startowy licznik losowo, żeby boty nie myślały w tej samej klatce
	ai_think_timer = randf_range(0.0, ai_answer_time)
	_dbg("=== AI gotowy [%s] ===" % Difficulty.keys()[int(difficulty)])

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

	_execute_move(delta)
	
func _dbg(msg: String):
	if GameManager.debug_enabled:
		var alive = "LIVING"
		if bot_node and bot_node.get(BOT_IS_ALIVE) == false:
			alive = "DEAD"
		var state_str = BotState.keys()[current_state] if current_state != null else "NONE"
		print("[BotAI %d | %s | %s] %s" % [bot_node.player_id if bot_node else 0, alive, state_str, msg])

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
	# Bomby i płonący ogień też są przeszkodą: przez bombę fizycznie się nie przejdzie, a ścieżka
	# ucieczki przez ogień kończyła się śmiercią.
	for bomb in get_tree().get_nodes_in_group(GROUP_BOMB):
		var bc := _cell(bomb.global_position)
		if not _out_of_bounds(bc):
			astar_grid.set_point_solid(bc, true)
	for exp in get_tree().get_nodes_in_group("explosion"):
		var ec := _cell(exp.global_position)
		if not _out_of_bounds(ec):
			astar_grid.set_point_solid(ec, true)
	# Pole bota zostaje przejezdne (stoi na własnej bombie) — A* z zablokowanego startu nie zwraca ścieżki.
	var own := _cell(bot_node.global_position)
	if not _out_of_bounds(own):
		astar_grid.set_point_solid(own, false)

# =====================
# DANGER MAP
# =====================
## danger_map: pole → sekundy do ognia (0 = płonie). Bomby w zasięgu wcześniejszej wybuchają razem z nią.
func _update_sense():
	danger_map.clear()
	_refresh_astar()

	var bombs: Array[Dictionary] = []
	for bomb in get_tree().get_nodes_in_group(GROUP_BOMB):
		bombs.append({
			"cell": _cell(bomb.global_position),
			"range": int(bomb.get("explosion_range")) if bomb.get("explosion_range") != null else 1,
			"t": bomb.time_left() if bomb.has_method("time_left") else BOMB_FUSE,
			# Kopnięta bomba: wybuch może nastąpić na każdym polu przed nią, aż do przeszkody.
			"slide": bomb.slide_path() if bomb.has_method("slide_path") else [],
		})
	var changed := true
	while changed:
		changed = false
		for a in bombs:
			var cells := _blast_cells(a["cell"], a["range"])
			for b in bombs:
				if b["t"] > a["t"] and cells.has(b["cell"]):
					b["t"] = a["t"]
					changed = true
	for a in bombs:
		_mark_danger(a["cell"], a["range"], a["t"])
		for c in a["slide"]:
			_mark_danger(c, a["range"], a["t"])

	if arena and arena.has_method("sudden_death_danger"):
		for c in arena.sudden_death_danger():
			_set_danger(c, SUDDEN_DEATH_DANGER_TIME)

	for exp in get_tree().get_nodes_in_group("explosion"):
		_set_danger(_cell(exp.global_position), 0.0)

	# Trasy omijają pola w zasięgu bomb, jeśli tylko się da (ucieczka przez cudzy wybuch kończyła się śmiercią).
	for x in range(grid_width):
		for y in range(grid_height):
			var c := Vector2i(x, y)
			astar_grid.set_point_weight_scale(c, DANGER_PATH_WEIGHT if danger_map.has(c) else 1.0)


func _mark_danger(bpos: Vector2i, power: int, time_left: float = BOMB_FUSE):
	for cp in _blast_cells(bpos, power):
		_set_danger(cp, time_left)


func _set_danger(cell: Vector2i, time_left: float) -> void:
	danger_map[cell] = minf(danger_map.get(cell, INF), time_left)

# =====================
# FSM
# =====================
func _machine_update():
	if not _action_complete:
		_on_step()
		return

	var entry := _check_transitions()
	var next: BotState = entry.state

	if next != current_state:
		_dbg("TRANSITION: %s -> %s" % [BotState.keys()[current_state], BotState.keys()[next]])
		_exit_state(current_state)
		current_state = next
		_cur_entry = entry
		_state_repeat = 0
		_enter_state(current_state)
	else:
		_cur_entry = entry
		_state_repeat += 1
		if _state_repeat >= 5:
			# Bomb It AIEngine: 5 razy ten sam stan → stan domyślny
			_dbg("stateRepeat >= 5 — stan domyślny.")
			_state_repeat = 0
			if current_state != _default_entry.state:
				_exit_state(current_state)
				current_state = _default_entry.state as BotState
				_cur_entry = _default_entry
				_enter_state(current_state)
			return

	_update_state(current_state)

## Bomb It AIEngine: stany w kolejności z profilu, pierwszy pasujący wygrywa; żaden — stan domyślny.
func _check_transitions() -> StateEntry:
	for e in _entries:
		if randf() > e.chance:
			continue
		var ok := false
		match e.state:
			BotState.ESCAPE:   ok = _check_escape()
			BotState.ATTACK:   ok = _check_attack()
			BotState.GET_ITEM: ok = _check_get_item()
			BotState.BOX:      ok = _check_box()
			BotState.FREE:     ok = _random_free_cell(_cell(bot_node.global_position)) != Vector2i(-1, -1)
			BotState.IDLE:     ok = not _bot_in_danger()
		if ok:
			return e
	return _default_entry

func _check_attack() -> bool:
	if _active_bombs() >= _max_bombs(): return false
	var pos := _cell(bot_node.global_position)
	var enemy := _nearest_enemy(pos)
	if enemy == Vector2i(-1, -1): return false
	
	# BARDZO WAŻNE: Najpierw szukamy miejsca do ataku.
	var apos := _find_attack_pos(enemy, pos)
	if apos == Vector2i(-1, -1): return false # Brak możliwości dojazdu by zaatakować
	
	# Upewniamy się, że w docelowym miejscu ataku da się posadzić bombę i uciec!
	return _plant_bomb_possible(apos)

func _check_escape() -> bool:
	if not _bot_in_danger(): return false
	var pos := _cell(bot_node.global_position)
	# Bez drogi ucieczki (potrzask) ESCAPE odpada — bot z rozpaczy szuka innej akcji.
	return not danger_map.has(pos) or not _escape_route(pos).is_empty() or _best_escape(pos) != Vector2i(-1, -1)

func _check_get_item() -> bool:
	if get_tree().get_nodes_in_group(GROUP_POWERUP).is_empty(): return false
	return _nearest_item(_cell(bot_node.global_position)) != Vector2i(-1, -1)

func _check_box() -> bool:
	if _active_bombs() >= _max_bombs(): return false
	if not arena or not arena.has_method("is_breakable"): return false
	var pos := _cell(bot_node.global_position)
	var box := _nearest_box(pos)
	if box == Vector2i(-1, -1): return false
	return float((box - pos).length()) <= float(find_range)

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
			_idle_left = IDLE_TIME
			_dbg("Stoję (IDLE).")
		BotState.FREE:
			var spot := _random_free_cell(pos)
			_dbg("Spaceruję na %s." % spot)
			_try_set_path(pos, spot)
		BotState.ESCAPE:
			_set_escape_path(pos)
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
	if to == Vector2i(-1, -1):
		_dbg("Anulowano szukanie ścieżki: brak bezpiecznego celu.")
		_action_complete = true
		return
	
	if to == from:
		_dbg("Cel to obecna kratka! Centruję pozycję bota.")
		# Zamiast odpuszczać, każemy mu dojść idealnie do środka jego obecnego pola.
		# Pozwoli to na fizyczne zebranie przedmiotu lub postawienie bomby.
		current_path = [from]
		return
	
	astar_grid.set_point_solid(from, false)
	var path := astar_grid.get_id_path(from, to)
	
	if path.size() > 0:
		if path[0] == from: 
			path.remove_at(0)
		
		# Jeśli po usunięciu startu ścieżka jest pusta (cel był obok i A* głupieje)
		if path.size() == 0:
			current_path = [from]
			return
			
		if _path_safe(path):
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
	var e := _cur_entry if _cur_entry else _default_entry

	if current_state == BotState.IDLE:
		_idle_left -= ai_answer_time
		if _idle_left <= 0.0 or _bot_in_danger():
			_action_complete = true
		return

	# Ucieczka: ktoś położył nową bombę i trasa przestała zdążać przed ogniem — nowa trasa
	# (bez lepszej biegnie dalej starą).
	if current_state == BotState.ESCAPE:
		if not current_path.is_empty() and not _route_in_time(current_path):
			var route := _escape_route(_cell(bot_node.global_position))
			if not route.is_empty():
				_dbg("Trasa ucieczki nie zdąży — nowa do %s." % route[-1])
				current_path = route
		return

	# stepDodge (advanceDodge, jak Bomb It): groźne pole bota, następne albo cel — przerwij ścieżkę (poza ucieczką)
	if current_state != BotState.ESCAPE and randf() < e.dodge and _step_in_danger():
		_dbg("stepDodge! Następna kratka jest zagrożona. Zatrzymuję ruch i czyszczę ścieżkę.")
		current_path.clear()
		_action_complete = true
		return

	# stepAttack (advanceAttack): przeciwnik w zasięgu po drodze — bomba w biegu
	if current_state != BotState.ESCAPE and randf() < e.attack and _active_bombs() < _max_bombs():
		var pos := _cell(bot_node.global_position)
		var enemy := _nearest_enemy(pos)
		if enemy != Vector2i(-1, -1) and _can_hit(pos, enemy) and _plant_bomb_possible(pos):
			_dbg("stepAttack: Kładę bombę 'w biegu'!")
			bot_node.set(BOT_BOMB_PROP, true)
			_mark_danger(pos, _bomb_range())
			current_path.clear()
			_exit_state(current_state)
			current_state = BotState.ESCAPE
			_enter_state(BotState.ESCAPE)

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

	# 4. USTALANIE KIERUNKU. Bot zatrzymany między polami najpierw wraca na środek swojego pola w osi
	# poprzecznej — inaczej skos w bok zahacza o róg bloku, „utyka” i porzuca ucieczkę.
	var dir := Vector2.ZERO
	var my_cell := _cell(bot_node.global_position)
	var my_center := Vector2(my_cell.x * grid_size + grid_size * 0.5, my_cell.y * grid_size + grid_size * 0.5)
	var off := my_center - bot_node.global_position
	var step := next_cell - my_cell
	if step.x != 0 and step.y == 0 and abs(off.y) > ALIGN_TOLERANCE:
		dir.y = sign(off.y)
	elif step.y != 0 and step.x == 0 and abs(off.x) > ALIGN_TOLERANCE:
		dir.x = sign(off.x)
	elif abs(diff.x) > abs(diff.y):
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
				# Bomba powstanie dopiero w następnej klatce gracza — bez tego własne pole
				# wyglądało na bezpieczne i ucieczka kończyła się w miejscu.
				_mark_danger(pos, _bomb_range())
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
## Czy po położeniu bomby na pos da się z niej uciec na czas (symulacja nowej bomby w mapie zagrożenia).
func _plant_bomb_possible(pos: Vector2i) -> bool:
	var sim := danger_map.duplicate()
	for cp in _blast_cells(pos, _bomb_range()):
		sim[cp] = minf(sim.get(cp, INF), BOMB_FUSE)
	return not _escape_route(pos, sim).is_empty()

func _best_escape(start: Vector2i) -> Vector2i:
	if not danger_map.has(start):
		return start
	var queue := [start]
	var visited := {start: true}
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	dirs.shuffle() # Sprawi, że przy każdym zapytaniu priorytety będą inne!
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


## Trasa ucieczki: najpierw z czasem (_escape_route), w potrzasku — najbliższe bezpieczne pole przez A*.
func _set_escape_path(pos: Vector2i) -> void:
	if not danger_map.has(pos):
		current_path = [pos]   # stoi na granicy pól — dojdź do środka bezpiecznego
		return
	var route := _escape_route(pos)
	if not route.is_empty():
		current_path = route
		_dbg("Ucieczka do %s (%d pól)." % [route[-1], route.size()])
		return
	var safe := _best_escape(pos)
	_dbg("Ucieczka bez zapasu czasu do %s." % safe)
	_try_set_path(pos, safe)


## Ucieczka z czasem: BFS tylko przez pola, które bot zdąży przejść przed ogniem; cel = najbliższe pole poza
## zagrożeniem. Trasa bez pola startowego ([] = brak).
func _escape_route(start: Vector2i, danger: Dictionary = danger_map) -> Array[Vector2i]:
	var st := _step_time()
	var parent := {start: start}
	var depth := {start: 0}
	var queue: Array[Vector2i] = [start]
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	dirs.shuffle()
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur != start and not danger.has(cur):
			var route: Array[Vector2i] = []
			while cur != start:
				route.push_front(cur)
				cur = parent[cur]
			return route
		for d in dirs:
			var nb: Vector2i = cur + d
			if _out_of_bounds(nb) or parent.has(nb) or astar_grid.is_point_solid(nb):
				continue
			# Pole trzeba minąć: dojść do niego i zejść z niego przed ogniem
			if danger.has(nb) and danger[nb] < (depth[cur] + 2) * st + ESCAPE_MARGIN:
				continue
			parent[nb] = cur
			depth[nb] = depth[cur] + 1
			queue.push_back(nb)
	return []


## Czy bot zdąży przejść trasę przed ogniem (cel może być zagrożony najwyżej później niż za sekundę od dojścia).
func _route_in_time(route: Array[Vector2i]) -> bool:
	var st := _step_time()
	for i in route.size():
		var c := route[i]
		var need := (i + 2) * st + ESCAPE_MARGIN + (1.0 if i == route.size() - 1 else 0.0)
		if danger_map.has(c) and danger_map[c] < need:
			return false
	return true


## Sekundy na przejście jednego pola przy obecnej szybkości bota.
func _step_time() -> float:
	var speed := float(bot_node.MOVE_SPEED) * float(bot_node.get("speed_mult")) * float(bot_node.get("move_speed_scale"))
	return float(grid_size) / maxf(speed, 1.0)

func _nearest_box(start: Vector2i) -> Vector2i:
	if not arena or not arena.has_method("is_breakable"):
		return Vector2i(-1, -1)
	var queue := [start]
	var visited := {start: true}
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	dirs.shuffle() # Sprawi, że przy każdym zapytaniu priorytety będą inne!
	var rlimit := float(find_range)
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
	dirs.shuffle() # Sprawi, że przy każdym zapytaniu priorytety będą inne!
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
	var rlimit := float(find_range)
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
				# Zmiana: Akceptujemy ścieżkę jeśli jest >0 ALBO gdy już stoimy na docelowym miejscu
				if (path.size() > 0 or bot_pos == cand) and _path_safe(path):
					return cand
	return Vector2i(-1, -1)

func _can_hit(from: Vector2i, target: Vector2i) -> bool:
	return _blast_cells(from, _bomb_range()).has(target)


## Ten sam zasięg co prawdziwy wybuch (arena.blast_cells).
func _blast_cells(origin: Vector2i, power: int) -> Array[Vector2i]:
	if arena and arena.has_method("blast_cells"):
		return arena.blast_cells(origin, power)
	return [origin]

func _path_safe(path: Array[Vector2i]) -> bool:
	if current_state == BotState.ESCAPE: 
		return true 
		
	for cell in path:
		if danger_map.has(cell): 
			return false
	return true

func _step_in_danger() -> bool:
	if _bot_in_danger():
		return true
	if current_path.is_empty():
		return false
	return danger_map.has(current_path[0]) or danger_map.has(current_path[-1])

func _bot_in_danger() -> bool:
	var center := bot_node.global_position
	for cell: Vector2i in danger_map:
		var cc := Vector2(cell.x * grid_size + grid_size * 0.5,
						  cell.y * grid_size + grid_size * 0.5)
		if center.distance_to(cc) < float(grid_size) * 0.9:
			return true
	return false

## Bomb It StateFree: losowe bezpieczne pole w zasięgu widzenia, do którego da się dojść.
func _random_free_cell(start: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	var queue := [start]
	var visited := {start: true}
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur != start and not danger_map.has(cur):
			options.append(cur)
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nb: Vector2i = cur + d
			if _out_of_bounds(nb) or visited.has(nb) or astar_grid.is_point_solid(nb) or danger_map.has(nb):
				continue
			if absi(nb.x - start.x) + absi(nb.y - start.y) > find_range:
				continue
			visited[nb] = true
			queue.push_back(nb)
	return options.pick_random() if not options.is_empty() else Vector2i(-1, -1)


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
	return int(bot_node.get(BOT_BOMB_RANGE)) if bot_node.get(BOT_BOMB_RANGE) != null else 1
