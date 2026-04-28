extends Node2D

const PLAYER_SCENE = preload("res://scenes/players/player.tscn")

const GRID_SIZE   : int = 64
const COLS        : int = 13
const ROWS        : int = 13

const COLOR_BG           = Color(0.15, 0.15, 0.17, 1.0)
const COLOR_GRID_LINE    = Color(0.22, 0.22, 0.25, 1.0)
const COLOR_SOLID        = Color(0.40, 0.42, 0.50, 1.0)
const COLOR_SOLID_HL     = Color(0.55, 0.57, 0.68, 1.0)
const COLOR_BREAKABLE    = Color(0.55, 0.38, 0.22, 1.0)  # brązowy
const COLOR_BREAKABLE_HL = Color(0.72, 0.52, 0.32, 1.0)

## Niezniszczalne komórki
var solid_cells: Dictionary = {}      # Vector2i -> true
## Zniszczalne komórki
var breakable_cells: Dictionary = {}  # Vector2i -> Node (StaticBody2D)

## Bezpieczna strefa wokół spawnow graczów (nie stawiamy tu skrzynek)
const SAFE_SPAWN_RADIUS : int = 2
const SPAWN_P1 := Vector2i(1, 1)
const SPAWN_P2 := Vector2i(11, 11)

@onready var players_root : Node2D = $Players
@onready var p1_spawn     : Marker2D = $P1Spawn
@onready var p2_spawn     : Marker2D = $P2Spawn


func _ready() -> void:
	_build_map()
	_spawn_players()
	RoundManager.start_round()
	RoundManager.last_chance_resolved.connect(_on_last_chance_resolved)


# ---------------------------------------------------------------------------
# Budowanie mapy
# ---------------------------------------------------------------------------

func _build_map() -> void:
	var map_node = Node2D.new()
	map_node.name = "Map"
	add_child(map_node)
	move_child(map_node, 0)

	for row in range(ROWS):
		for col in range(COLS):
			var cell = Vector2i(col, row)
			var px   = Vector2(col * GRID_SIZE, row * GRID_SIZE)

			if _is_solid(cell):
				solid_cells[cell] = true
				_spawn_solid_block(map_node, px)
			elif _should_be_breakable(cell):
				var b = _spawn_breakable_block(map_node, px)
				breakable_cells[cell] = b
			else:
				_spawn_floor_tile(map_node, px)


## Niezniszczalne: obramowanie + parzyste-parzyste wnętrze
func _is_solid(cell: Vector2i) -> bool:
	if cell.x == 0 or cell.x == COLS - 1: return true
	if cell.y == 0 or cell.y == ROWS - 1: return true
	return cell.x % 2 == 0 and cell.y % 2 == 0


## Zniszczalne: wolne komórki które nie są w bezpiecznej strefie spawnow
func _should_be_breakable(cell: Vector2i) -> bool:
	if _is_solid(cell): return false
	# Zostaw wolną strefę wokół P1 i P2
	if _near_spawn(cell, SPAWN_P1): return false
	if _near_spawn(cell, SPAWN_P2): return false
	return true


func _near_spawn(cell: Vector2i, spawn: Vector2i) -> bool:
	var dx = abs(cell.x - spawn.x)
	var dy = abs(cell.y - spawn.y)
	return dx + dy <= SAFE_SPAWN_RADIUS


# ---------------------------------------------------------------------------
# Spawning bloków
# ---------------------------------------------------------------------------

func _spawn_solid_block(parent: Node, px: Vector2) -> void:
	var body = StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE / 2, GRID_SIZE / 2)
	body.collision_layer = 1
	body.collision_mask  = 2
	parent.add_child(body)

	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size = Vector2(GRID_SIZE, GRID_SIZE)
	shape.shape = rect
	body.add_child(shape)

	var cr = ColorRect.new()
	cr.size = Vector2(GRID_SIZE, GRID_SIZE)
	cr.position = Vector2(-GRID_SIZE / 2, -GRID_SIZE / 2)
	cr.color = COLOR_SOLID
	body.add_child(cr)

	var hl = ColorRect.new()
	hl.size = Vector2(GRID_SIZE - 4, 4)
	hl.position = Vector2(-GRID_SIZE / 2 + 2, -GRID_SIZE / 2 + 2)
	hl.color = COLOR_SOLID_HL
	body.add_child(hl)

	var hl2 = ColorRect.new()
	hl2.size = Vector2(4, GRID_SIZE - 4)
	hl2.position = Vector2(-GRID_SIZE / 2 + 2, -GRID_SIZE / 2 + 2)
	hl2.color = COLOR_SOLID_HL
	body.add_child(hl2)


func _spawn_breakable_block(parent: Node, px: Vector2) -> Node:
	var body = StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE / 2, GRID_SIZE / 2)
	body.collision_layer = 1
	body.collision_mask  = 2
	body.add_to_group("breakable")
	parent.add_child(body)

	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size = Vector2(GRID_SIZE - 2, GRID_SIZE - 2)
	shape.shape = rect
	body.add_child(shape)

	var cr = ColorRect.new()
	cr.size = Vector2(GRID_SIZE, GRID_SIZE)
	cr.position = Vector2(-GRID_SIZE / 2, -GRID_SIZE / 2)
	cr.color = COLOR_BREAKABLE
	body.add_child(cr)

	var hl = ColorRect.new()
	hl.size = Vector2(GRID_SIZE - 4, 4)
	hl.position = Vector2(-GRID_SIZE / 2 + 2, -GRID_SIZE / 2 + 2)
	hl.color = COLOR_BREAKABLE_HL
	body.add_child(hl)

	var hl2 = ColorRect.new()
	hl2.size = Vector2(4, GRID_SIZE - 4)
	hl2.position = Vector2(-GRID_SIZE / 2 + 2, -GRID_SIZE / 2 + 2)
	hl2.color = COLOR_BREAKABLE_HL
	body.add_child(hl2)

	return body


func _spawn_floor_tile(parent: Node, px: Vector2) -> void:
	var n = Node2D.new()
	n.position = px
	parent.add_child(n)

	var bg = ColorRect.new()
	bg.size = Vector2(GRID_SIZE, GRID_SIZE)
	bg.color = COLOR_BG
	n.add_child(bg)

	var lr = ColorRect.new()
	lr.size = Vector2(1, GRID_SIZE)
	lr.position = Vector2(GRID_SIZE - 1, 0)
	lr.color = COLOR_GRID_LINE
	n.add_child(lr)

	var lb = ColorRect.new()
	lb.size = Vector2(GRID_SIZE, 1)
	lb.position = Vector2(0, GRID_SIZE - 1)
	lb.color = COLOR_GRID_LINE
	n.add_child(lb)


# ---------------------------------------------------------------------------
# API dla bomb.gd i explosion.gd
# ---------------------------------------------------------------------------

func is_solid(cell: Vector2i) -> bool:
	return solid_cells.has(cell)

func is_breakable(cell: Vector2i) -> bool:
	return breakable_cells.has(cell)

## Niszczy blok i usuwa go z mapy. Zwraca true jeśli był zniszczalny.
func break_cell(cell: Vector2i) -> bool:
	if not breakable_cells.has(cell):
		return false
	var node = breakable_cells[cell]
	breakable_cells.erase(cell)
	if is_instance_valid(node):
		node.queue_free()
	return true

func pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


# ---------------------------------------------------------------------------
# Gracze
# ---------------------------------------------------------------------------

func _spawn_players() -> void:
	var p1 = PLAYER_SCENE.instantiate()
	p1.player_id = 1
	p1.is_bot    = false
	p1.global_position = p1_spawn.global_position
	players_root.add_child(p1)

	if GameManager.num_human_players >= 2:
		var p2 = PLAYER_SCENE.instantiate()
		p2.player_id = 2
		p2.is_bot    = false
		p2.global_position = p2_spawn.global_position
		players_root.add_child(p2)
	else:
		var bot = PLAYER_SCENE.instantiate()
		bot.player_id = 2
		bot.is_bot    = true
		bot.global_position = p2_spawn.global_position
		players_root.add_child(bot)


func _on_last_chance_resolved(dead_player_id: int, respawned: bool) -> void:
	for child in players_root.get_children():
		if child.player_id == dead_player_id:
			child.resolve_last_chance(respawned)
