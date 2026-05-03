extends Node2D

## Scena areny odpowiada TYLKO za mapę:
## budowanie siatki, kolizje, API dla bomb/eksplozji, spawn pointy.
## Gracze są spawnowani przez game.gd.

const GRID_SIZE : int = 64
const COLS      : int = 13
const ROWS      : int = 13

const COLOR_BG           = Color(0.15, 0.15, 0.17, 1.0)
const COLOR_GRID_LINE    = Color(0.22, 0.22, 0.25, 1.0)
const COLOR_SOLID        = Color(0.40, 0.42, 0.50, 1.0)
const COLOR_SOLID_HL     = Color(0.55, 0.57, 0.68, 1.0)
const COLOR_BREAKABLE    = Color(0.55, 0.38, 0.22, 1.0)
const COLOR_BREAKABLE_HL = Color(0.72, 0.52, 0.32, 1.0)

var solid_cells    : Dictionary = {}
var breakable_cells: Dictionary = {}
var powerup_cells  : Dictionary = {}   # Vector2i → Node (power-up leżący na planszy)

const SAFE_SPAWN_RADIUS : int = 2

const SPAWN_POINTS : Array[Vector2i] = [
	Vector2i(1,  1),   # P1   — lewy górny
	Vector2i(11, 11),  # P2   — prawy dolny
	Vector2i(11, 1),   # Bot1 — prawy górny
	Vector2i(1,  11),  # Bot2 — lewy dolny
]

## Prawdopodobieństwo spawna power-upa po zniszczeniu skrzynki
const POWERUP_CHANCE : float = 0.40

const POWERUP_SCENE = preload("res://scenes/objects/powerup.tscn")

## Pula typów (wagi: range_up 3×, bomb_up 3×, speed_up 2×, life_up 1×)
const POWERUP_POOL : Array[String] = [
	"range_up", "range_up", "range_up",
	"bomb_up",  "bomb_up",  "bomb_up",
	"speed_up", "speed_up",
	"life_up",
]


func _ready() -> void:
	_setup_camera()
	_build_map()


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
	var viewport  := get_viewport().get_visible_rect().size
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
	var map_node := Node2D.new()
	map_node.name = "Map"
	add_child(map_node); move_child(map_node, 0)

	for row in range(ROWS):
		for col in range(COLS):
			var cell := Vector2i(col, row)
			var px   := Vector2(col * GRID_SIZE, row * GRID_SIZE)
			if _is_solid(cell):
				solid_cells[cell] = true
				_spawn_solid_block(map_node, px)
			elif _should_be_breakable(cell):
				breakable_cells[cell] = _spawn_breakable_block(map_node, px)
			else:
				_spawn_floor_tile(map_node, px)


func _is_solid(cell: Vector2i) -> bool:
	if cell.x == 0 or cell.x == COLS - 1: return true
	if cell.y == 0 or cell.y == ROWS - 1: return true
	return cell.x % 2 == 0 and cell.y % 2 == 0


func _should_be_breakable(cell: Vector2i) -> bool:
	if _is_solid(cell): return false
	for sp: Vector2i in SPAWN_POINTS:
		if _near_spawn(cell, sp): return false
	return (_is_solid(cell + Vector2i(-1,0)) and _is_solid(cell + Vector2i(1,0))) \
		or (_is_solid(cell + Vector2i(0,-1)) and _is_solid(cell + Vector2i(0,1)))


func _near_spawn(cell: Vector2i, spawn: Vector2i) -> bool:
	return abs(cell.x - spawn.x) + abs(cell.y - spawn.y) <= SAFE_SPAWN_RADIUS


# ---------------------------------------------------------------------------
# Spawning bloków
# ---------------------------------------------------------------------------

func _spawn_solid_block(parent: Node, px: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE/2, GRID_SIZE/2)
	body.collision_layer = 1; body.collision_mask = 2
	parent.add_child(body)
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new(); rect.size = Vector2(GRID_SIZE, GRID_SIZE)
	shape.shape = rect; body.add_child(shape)
	_add_color_rect(body, Vector2(GRID_SIZE, GRID_SIZE), Vector2(-GRID_SIZE/2,-GRID_SIZE/2), COLOR_SOLID)
	_add_color_rect(body, Vector2(GRID_SIZE-4, 4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_SOLID_HL)
	_add_color_rect(body, Vector2(4, GRID_SIZE-4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_SOLID_HL)


func _spawn_breakable_block(parent: Node, px: Vector2) -> Node:
	var body := StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE/2, GRID_SIZE/2)
	body.collision_layer = 1; body.collision_mask = 2
	body.add_to_group("breakable"); parent.add_child(body)
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new(); rect.size = Vector2(GRID_SIZE, GRID_SIZE)
	shape.shape = rect; body.add_child(shape)
	_add_color_rect(body, Vector2(GRID_SIZE, GRID_SIZE), Vector2(-GRID_SIZE/2,-GRID_SIZE/2), COLOR_BREAKABLE)
	_add_color_rect(body, Vector2(GRID_SIZE-4, 4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_BREAKABLE_HL)
	_add_color_rect(body, Vector2(4, GRID_SIZE-4), Vector2(-GRID_SIZE/2+2,-GRID_SIZE/2+2), COLOR_BREAKABLE_HL)
	return body


func _spawn_floor_tile(parent: Node, px: Vector2) -> void:
	var n := Node2D.new(); n.position = px; parent.add_child(n)
	_add_color_rect(n, Vector2(GRID_SIZE, GRID_SIZE), Vector2.ZERO, COLOR_BG)
	_add_color_rect(n, Vector2(1, GRID_SIZE), Vector2(GRID_SIZE-1, 0), COLOR_GRID_LINE)
	_add_color_rect(n, Vector2(GRID_SIZE, 1), Vector2(0, GRID_SIZE-1), COLOR_GRID_LINE)


func _add_color_rect(parent: Node, sz: Vector2, pos: Vector2, col: Color) -> void:
	var cr := ColorRect.new(); cr.size = sz; cr.position = pos; cr.color = col
	parent.add_child(cr)


# ---------------------------------------------------------------------------
# Publiczne API — używane przez bomb.gd, explosion.gd, game.gd
# ---------------------------------------------------------------------------

func is_solid(cell: Vector2i) -> bool:     return solid_cells.has(cell)
func is_breakable(cell: Vector2i) -> bool: return breakable_cells.has(cell)
func has_powerup(cell: Vector2i) -> bool:  return powerup_cells.has(cell)

func break_cell(cell: Vector2i) -> bool:
	if not breakable_cells.has(cell): return false
	var node = breakable_cells[cell]
	breakable_cells.erase(cell)
	if is_instance_valid(node): node.queue_free()
	# Szansa na spawn power-upa
	if randf() < POWERUP_CHANCE:
		_spawn_powerup(cell)
	return true


func _spawn_powerup(cell: Vector2i) -> void:
	var pu   := POWERUP_SCENE.instantiate()
	var type : String = POWERUP_POOL[randi() % POWERUP_POOL.size()]
	pu.powerup_type    = type
	pu.position        = Vector2(cell.x * GRID_SIZE, cell.y * GRID_SIZE)
	pu.collected.connect(_on_powerup_collected.bind(cell))
	add_child(pu)
	powerup_cells[cell] = pu


func _on_powerup_collected(type: String, cell: Vector2i) -> void:
	powerup_cells.erase(cell)


func pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))

## Pixel-center n-tego spawna — używane przez game.gd
func spawn_pixel(idx: int) -> Vector2:
	var sp : Vector2i = SPAWN_POINTS[idx % SPAWN_POINTS.size()]
	return Vector2(sp.x * GRID_SIZE + GRID_SIZE / 2, sp.y * GRID_SIZE + GRID_SIZE / 2)
