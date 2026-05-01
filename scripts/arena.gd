extends Node2D

const PLAYER_SCENE = preload("res://scenes/players/player.tscn")

const GRID_SIZE   : int = 64
const COLS        : int = 13
const ROWS        : int = 13

const COLOR_BG           = Color(0.15, 0.15, 0.17, 1.0)
const COLOR_GRID_LINE    = Color(0.22, 0.22, 0.25, 1.0)
const COLOR_SOLID        = Color(0.40, 0.42, 0.50, 1.0)
const COLOR_SOLID_HL     = Color(0.55, 0.57, 0.68, 1.0)
const COLOR_BREAKABLE    = Color(0.55, 0.38, 0.22, 1.0)
const COLOR_BREAKABLE_HL = Color(0.72, 0.52, 0.32, 1.0)

var solid_cells: Dictionary = {}
var breakable_cells: Dictionary = {}

const SAFE_SPAWN_RADIUS : int = 2
const SPAWN_P1 := Vector2i(1, 1)
const SPAWN_P2 := Vector2i(11, 11)

@onready var players_root : Node2D   = $Players
@onready var p1_spawn     : Marker2D = $P1Spawn
@onready var p2_spawn     : Marker2D = $P2Spawn

## Śledź graczy — potrzebne do _check_round_end()
var _players: Array = []


func _ready() -> void:
	_setup_camera()
	_build_map()
	_spawn_players()
	RoundManager.start_round()
	RoundManager.last_chance_resolved.connect(_on_last_chance_resolved)


# ---------------------------------------------------------------------------
# Kamera
# ---------------------------------------------------------------------------

func _setup_camera() -> void:
	var map_pixel_size := Vector2(COLS * GRID_SIZE, ROWS * GRID_SIZE)
	var map_center     := map_pixel_size * 0.5
	var cam := Camera2D.new()
	cam.position = map_center
	cam.zoom     = _calc_zoom(map_pixel_size)
	cam.limit_left   = 0; cam.limit_top    = 0
	cam.limit_right  = int(map_pixel_size.x)
	cam.limit_bottom = int(map_pixel_size.y)
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()
	get_tree().root.size_changed.connect(_on_window_resized.bind(cam, map_pixel_size, map_center))


func _calc_zoom(map_size: Vector2) -> Vector2:
	var viewport := get_viewport().get_visible_rect().size
	var available := Vector2(viewport.x, viewport.y - 48)
	if available.x <= 0 or available.y <= 0:
		return Vector2.ONE
	var s := minf(available.x / map_size.x, available.y / map_size.y)
	return Vector2(s, s)


func _on_window_resized(cam: Camera2D, map_size: Vector2, center: Vector2) -> void:
	cam.zoom = _calc_zoom(map_size); cam.position = center


# ---------------------------------------------------------------------------
# Budowanie mapy
# ---------------------------------------------------------------------------

func _build_map() -> void:
	var map_node = Node2D.new()
	map_node.name = "Map"
	add_child(map_node); move_child(map_node, 0)

	for row in range(ROWS):
		for col in range(COLS):
			var cell = Vector2i(col, row)
			var px   = Vector2(col * GRID_SIZE, row * GRID_SIZE)
			if _is_solid(cell):
				solid_cells[cell] = true; _spawn_solid_block(map_node, px)
			elif _should_be_breakable(cell):
				breakable_cells[cell] = _spawn_breakable_block(map_node, px)
			else:
				_spawn_floor_tile(map_node, px)


func _is_solid(cell: Vector2i) -> bool:
	if cell.x == 0 or cell.x == COLS - 1: return true
	if cell.y == 0 or cell.y == ROWS - 1: return true
	return cell.x % 2 == 0 and cell.y % 2 == 0


func _should_be_breakable(cell: Vector2i) -> bool:
	if _is_solid(cell) or _near_spawn(cell, SPAWN_P1) or _near_spawn(cell, SPAWN_P2): return false
	return (_is_solid(cell + Vector2i(-1,0)) and _is_solid(cell + Vector2i(1,0))) \
		or (_is_solid(cell + Vector2i(0,-1)) and _is_solid(cell + Vector2i(0,1)))


func _near_spawn(cell: Vector2i, spawn: Vector2i) -> bool:
	return abs(cell.x - spawn.x) + abs(cell.y - spawn.y) <= SAFE_SPAWN_RADIUS


# ---------------------------------------------------------------------------
# Spawning bloków
# ---------------------------------------------------------------------------

func _spawn_solid_block(parent: Node, px: Vector2) -> void:
	var body = StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE/2, GRID_SIZE/2)
	body.collision_layer = 1; body.collision_mask = 2
	parent.add_child(body)
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new(); rect.size = Vector2(GRID_SIZE, GRID_SIZE)
	shape.shape = rect; body.add_child(shape)
	_add_color_rect(body, Vector2(GRID_SIZE, GRID_SIZE), Vector2(-GRID_SIZE/2,-GRID_SIZE/2), COLOR_SOLID)
	_add_color_rect(body, Vector2(GRID_SIZE-4, 4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_SOLID_HL)
	_add_color_rect(body, Vector2(4, GRID_SIZE-4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_SOLID_HL)


func _spawn_breakable_block(parent: Node, px: Vector2) -> Node:
	var body = StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE/2, GRID_SIZE/2)
	body.collision_layer = 1; body.collision_mask = 2
	body.add_to_group("breakable"); parent.add_child(body)
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new(); rect.size = Vector2(GRID_SIZE-2, GRID_SIZE-2)
	shape.shape = rect; body.add_child(shape)
	_add_color_rect(body, Vector2(GRID_SIZE, GRID_SIZE), Vector2(-GRID_SIZE/2,-GRID_SIZE/2), COLOR_BREAKABLE)
	_add_color_rect(body, Vector2(GRID_SIZE-4, 4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_BREAKABLE_HL)
	_add_color_rect(body, Vector2(4, GRID_SIZE-4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_BREAKABLE_HL)
	return body


func _spawn_floor_tile(parent: Node, px: Vector2) -> void:
	var n = Node2D.new(); n.position = px; parent.add_child(n)
	_add_color_rect(n, Vector2(GRID_SIZE, GRID_SIZE), Vector2.ZERO, COLOR_BG)
	_add_color_rect(n, Vector2(1, GRID_SIZE), Vector2(GRID_SIZE-1, 0), COLOR_GRID_LINE)
	_add_color_rect(n, Vector2(GRID_SIZE, 1), Vector2(0, GRID_SIZE-1), COLOR_GRID_LINE)


func _add_color_rect(parent: Node, sz: Vector2, pos: Vector2, col: Color) -> void:
	var cr = ColorRect.new(); cr.size = sz; cr.position = pos; cr.color = col
	parent.add_child(cr)


# ---------------------------------------------------------------------------
# API dla bomb.gd i explosion.gd
# ---------------------------------------------------------------------------

func is_solid(cell: Vector2i) -> bool:     return solid_cells.has(cell)
func is_breakable(cell: Vector2i) -> bool: return breakable_cells.has(cell)

func break_cell(cell: Vector2i) -> bool:
	if not breakable_cells.has(cell): return false
	var node = breakable_cells[cell]
	breakable_cells.erase(cell)
	if is_instance_valid(node): node.queue_free()
	return true

func pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


# ---------------------------------------------------------------------------
# Gracze
# ---------------------------------------------------------------------------

func _spawn_players() -> void:
	var hud: CanvasLayer = null
	if GameManager.game_node:
		hud = GameManager.game_node.get_active_hud()

	var p1 = PLAYER_SCENE.instantiate()
	p1.player_id = 1; p1.is_bot = false
	p1.global_position = p1_spawn.global_position
	players_root.add_child(p1)
	_players.append(p1)
	_connect_player(p1, hud)

	if GameManager.num_human_players >= 2:
		var p2 = PLAYER_SCENE.instantiate()
		p2.player_id = 2; p2.is_bot = false
		p2.global_position = p2_spawn.global_position
		players_root.add_child(p2)
		_players.append(p2)
		_connect_player(p2, hud)
	else:
		var bot = PLAYER_SCENE.instantiate()
		bot.player_id = 2; bot.is_bot = true
		bot.global_position = p2_spawn.global_position
		players_root.add_child(bot)
		_players.append(bot)
		bot.died.connect(_on_player_died)


## Podłącza HUD i sygnał died dla graczy ludzkich.
func _connect_player(player: CharacterBody2D, hud: CanvasLayer) -> void:
	player.died.connect(_on_player_died)
	if not hud:
		return
	hud.update_lives(player.player_id, player.lives, player.DEFAULT_LIVES)
	player.lives_changed.connect(
		func(pid: int, left: int): hud.update_lives(pid, left, player.DEFAULT_LIVES)
	)


## Wołane gdy gracz (lub bot) ostatecznie ginie.
func _on_player_died(dead_pid: int) -> void:
	# Poczekaj klatkę — drugi gracz mógł też zginąć w tej samej eksplozji
	get_tree().process_frame.connect(_deferred_check_round.bind(dead_pid), CONNECT_ONE_SHOT)


func _deferred_check_round(dead_pid: int) -> void:
	var alive_players: Array = []
	for p in _players:
		if is_instance_valid(p) and p.is_alive:
			alive_players.append(p)

	match alive_players.size():
		0:
			# Oboje zginęli jednocześnie — remis
			RoundManager.end_round(-1)
		1:
			# Jeden przeżył — wygrywa
			RoundManager.end_round(alive_players[0].player_id)
		_:
			# Więcej niż jeden żyje — gra trwa
			pass


func _on_last_chance_resolved(dead_player_id: int, respawned: bool) -> void:
	for p in _players:
		if is_instance_valid(p) and p.player_id == dead_player_id:
			p.resolve_last_chance(respawned)
			return
