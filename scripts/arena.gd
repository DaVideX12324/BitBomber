extends Node2D

const BBRuntime = preload("bb_runtime.gd")

## Scena areny odpowiada TYLKO za mapę:
## budowanie siatki, kolizje, API dla bomb/eksplozji, spawn pointy.
## Gracze są spawnowani przez game.gd.
##
## Układ z resources/maps/<id>.json (rows: '#' blok stały, 'C' środek mapy — też stały,
## 'b' miejsce na skrzynkę, '.' puste). Skrzynka staje na 'b' z szansą box_density —
## jak w Bomb It 7 (tools/import_bombit_maps.py).

const GRID_SIZE : int = 64
const MAPS_DIR  : String = "resources/maps"
## Mapa, gdy wybrana nie istnieje.
const FALLBACK_MAP : String = "classic"

const COLOR_BG           = Color(0.15, 0.15, 0.17, 1.0)
const COLOR_GRID_LINE    = Color(0.22, 0.22, 0.25, 1.0)
const COLOR_SOLID        = Color(0.40, 0.42, 0.50, 1.0)
const COLOR_SOLID_HL     = Color(0.55, 0.57, 0.68, 1.0)
const COLOR_CENTER       = Color(0.30, 0.36, 0.46, 1.0)
const COLOR_BREAKABLE    = Color(0.55, 0.38, 0.22, 1.0)
const COLOR_BREAKABLE_HL = Color(0.72, 0.52, 0.32, 1.0)

var cols : int = 0
var rows : int = 0
var map_id : String = ""

var solid_cells    : Dictionary = {}
var breakable_cells: Dictionary = {}
var powerup_cells  : Dictionary = {}   # Vector2i → Node (power-up leżący na planszy)

## Pola przy spawnie (Manhattan), na których nigdy nie stoi skrzynka.
const SAFE_SPAWN_RADIUS : int = 1

## Losowa permutacja spawnów mapy na tę rundę — ustawiana w _ready()
var spawn_points : Array[Vector2i] = []

var _rows_data : PackedStringArray = []

## Prawdopodobieństwo spawna power-upa po zniszczeniu skrzynki
const POWERUP_CHANCE : float = 0.40

var _powerup_scene: PackedScene = load(BBRuntime.path("scenes/objects/powerup.tscn"))

## Pula typów (wagi: range_up 4×, bomb_up 4×, speed_up 3×, life_up 1×)
const POWERUP_POOL : Array[String] = [
	"range_up", "range_up", "range_up", "range_up",
	"bomb_up",  "bomb_up",  "bomb_up",  "bomb_up",
	"speed_up", "speed_up", "speed_up",
	"life_up",
]


func _ready() -> void:
	add_to_group("arena")
	_load_layout(_pick_map_id())
	_randomize_spawns()
	_setup_camera()
	_build_map()


# ---------------------------------------------------------------------------
# Mapy
# ---------------------------------------------------------------------------

## Id wszystkich map (nazwy plików bez .json), posortowane.
static func list_maps() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in DirAccess.get_files_at(BBRuntime.path(MAPS_DIR)):
		if f.ends_with(".json"):
			ids.append(f.get_basename())
	ids.sort()
	return ids


static func load_map_data(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(BBRuntime.path("%s/%s.json" % [MAPS_DIR, id]))
	var data = JSON.parse_string(text)
	return data if data is Dictionary else {}


func _pick_map_id() -> String:
	var gm := get_node_or_null("/root/GameManager")
	var wanted : String = gm.selected_map if gm and gm.get("selected_map") != null else ""
	if wanted != "":
		return wanted
	var ids := list_maps()
	return ids[randi() % ids.size()] if not ids.is_empty() else FALLBACK_MAP


func _load_layout(id: String) -> void:
	var data := load_map_data(id)
	if data.is_empty():
		push_warning("Arena: brak mapy %s — %s" % [id, FALLBACK_MAP])
		id = FALLBACK_MAP
		data = load_map_data(id)
	map_id = id
	_rows_data = PackedStringArray(data.get("rows", []))
	rows = _rows_data.size()
	cols = _rows_data[0].length() if rows > 0 else 0
	spawn_points.clear()
	for sp in data.get("spawns", []):
		spawn_points.append(Vector2i(int(sp[0]), int(sp[1])))


func _box_density() -> float:
	var gm := get_node_or_null("/root/GameManager")
	return float(gm.box_density) if gm and gm.get("box_density") != null else 0.7


# ---------------------------------------------------------------------------
# Randomizacja spawnpointów
# ---------------------------------------------------------------------------

func _randomize_spawns() -> void:
	spawn_points.shuffle()


# ---------------------------------------------------------------------------
# Kamera
# ---------------------------------------------------------------------------

func _setup_camera() -> void:
	var map_pixel_size := Vector2(cols * GRID_SIZE, rows * GRID_SIZE)
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
	var density := _box_density()

	for row in range(rows):
		for col in range(cols):
			var cell := Vector2i(col, row)
			var px   := Vector2(col * GRID_SIZE, row * GRID_SIZE)
			var ch   := _rows_data[row][col]
			if ch == "#" or ch == "C":
				solid_cells[cell] = true
				_spawn_solid_block(map_node, px, COLOR_CENTER if ch == "C" else COLOR_SOLID)
			elif ch == "b" and not _near_any_spawn(cell) and randf() < density:
				breakable_cells[cell] = _spawn_breakable_block(map_node, px)
			else:
				_spawn_floor_tile(map_node, px)


func _near_any_spawn(cell: Vector2i) -> bool:
	for sp: Vector2i in spawn_points:
		if abs(cell.x - sp.x) + abs(cell.y - sp.y) <= SAFE_SPAWN_RADIUS:
			return true
	return false


# ---------------------------------------------------------------------------
# Spawning bloków
# ---------------------------------------------------------------------------

func _spawn_solid_block(parent: Node, px: Vector2, color: Color) -> Node2D:
	var body := StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE / 2.0, GRID_SIZE / 2.0)
	body.collision_layer = 1; body.collision_mask = 2
	parent.add_child(body)
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new(); rect.size = Vector2(GRID_SIZE, GRID_SIZE)
	shape.shape = rect; body.add_child(shape)
	_add_color_rect(body, Vector2(GRID_SIZE, GRID_SIZE), Vector2(-GRID_SIZE / 2.0, -GRID_SIZE / 2.0), color)
	_add_color_rect(body, Vector2(GRID_SIZE-4, 4), Vector2(-GRID_SIZE / 2.0 + 2.0, -GRID_SIZE / 2.0 + 2.0), COLOR_SOLID_HL)
	_add_color_rect(body, Vector2(4, GRID_SIZE-4), Vector2(-GRID_SIZE / 2.0 + 2.0, -GRID_SIZE / 2.0 + 2.0), COLOR_SOLID_HL)
	return body


func _spawn_breakable_block(parent: Node, px: Vector2) -> Node:
	var body := StaticBody2D.new()
	body.position = px + Vector2(GRID_SIZE / 2.0, GRID_SIZE / 2.0)
	body.collision_layer = 1; body.collision_mask = 2
	body.add_to_group("breakable"); parent.add_child(body)
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new(); rect.size = Vector2(GRID_SIZE, GRID_SIZE)
	shape.shape = rect; body.add_child(shape)
	_add_color_rect(body, Vector2(GRID_SIZE, GRID_SIZE), Vector2(-GRID_SIZE / 2.0, -GRID_SIZE / 2.0), COLOR_BREAKABLE)
	_add_color_rect(body, Vector2(GRID_SIZE-4, 4), Vector2(-GRID_SIZE / 2.0 + 2.0, -GRID_SIZE / 2.0 + 2.0), COLOR_BREAKABLE_HL)
	_add_color_rect(body, Vector2(4, GRID_SIZE-4), Vector2(-GRID_SIZE / 2.0 + 2.0, -GRID_SIZE / 2.0 + 2.0), COLOR_BREAKABLE_HL)
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


## Pola trafione wybuchem: środek + do `power` pól w każdą stronę.
## Ogień staje na ścianie, a skrzynkę zajmuje i dalej nie idzie.
func blast_cells(origin: Vector2i, power: int) -> Array[Vector2i]:
	var cells : Array[Vector2i] = [origin]
	for dir : Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		for i in range(1, power + 1):
			var cell : Vector2i = origin + dir * i
			if is_solid(cell): break
			cells.append(cell)
			if is_breakable(cell): break
	return cells

func break_cell(cell: Vector2i) -> bool:
	if not breakable_cells.has(cell): return false
	var node = breakable_cells[cell]
	breakable_cells.erase(cell)
	if is_instance_valid(node): node.queue_free()
	if randf() < POWERUP_CHANCE:
		_spawn_powerup(cell)
	return true


func _spawn_powerup(cell: Vector2i) -> void:
	var pu   := _powerup_scene.instantiate()
	var type : String = POWERUP_POOL[randi() % POWERUP_POOL.size()]
	pu.powerup_type    = type
	pu.position        = Vector2(cell.x * GRID_SIZE, cell.y * GRID_SIZE)
	pu.tree_exiting.connect(_on_powerup_gone.bind(cell))
	add_child(pu)
	powerup_cells[cell] = pu


## Zebrany albo spalony.
func _on_powerup_gone(cell: Vector2i) -> void:
	powerup_cells.erase(cell)


func pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))

## Pixel-center n-tego spawna (losowa permutacja co rundę)
func spawn_pixel(idx: int) -> Vector2:
	var sp : Vector2i = spawn_points[idx % spawn_points.size()]
	return Vector2(sp.x * GRID_SIZE + GRID_SIZE / 2.0, sp.y * GRID_SIZE + GRID_SIZE / 2.0)


# ---------------------------------------------------------------------------
# Nagła śmierć — po czasie rundy bloki spadają spiralą od krawędzi do środka
# ---------------------------------------------------------------------------

## Co tyle sekund spada blok.
const SUDDEN_DEATH_STEP : float = 0.2
## Ile kolejnych pól jest oznaczonych (i omijanych przez boty).
const SUDDEN_DEATH_WARN : int = 8
const COLOR_SUDDEN_WARN = Color(0.9, 0.15, 0.1, 0.35)

var _sd_order  : Array[Vector2i] = []
var _sd_timer  : float = 0.0
var _sd_warn   : Node2D = null


func start_sudden_death() -> void:
	_sd_order = _spiral_cells()
	_sd_timer = 0.0
	_sd_warn = Node2D.new()
	_sd_warn.name = "SuddenDeathWarn"
	_sd_warn.z_index = 1
	_sd_warn.draw.connect(_draw_sudden_warn)
	add_child(_sd_warn)


## Następne pola, na które spadną bloki.
func sudden_death_danger() -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	for c in _sd_order:
		if solid_cells.has(c):
			continue
		out.append(c)
		if out.size() >= SUDDEN_DEATH_WARN:
			break
	return out


## Najbliższe pole bez bloku i skrzynki (BFS po wszystkim w obrysie).
func nearest_free_cell(from: Vector2i) -> Vector2i:
	var seen := {from: true}
	var queue : Array[Vector2i] = [from]
	while not queue.is_empty():
		var c : Vector2i = queue.pop_front()
		if not solid_cells.has(c) and not breakable_cells.has(c):
			return c
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n : Vector2i = c + d
			if n.x > 0 and n.y > 0 and n.x < cols - 1 and n.y < rows - 1 and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return from


func _process(delta: float) -> void:
	if _sd_order.is_empty():
		return
	_sd_timer += delta
	while _sd_timer >= SUDDEN_DEATH_STEP and not _sd_order.is_empty():
		var cell : Vector2i = _sd_order.pop_front()
		if solid_cells.has(cell):
			continue
		_sd_timer -= SUDDEN_DEATH_STEP
		_drop_block(cell)
	if _sd_warn:
		_sd_warn.queue_redraw()


## Wnętrze mapy spiralą: górny wiersz w prawo, prawa kolumna w dół, dolny w lewo, lewa w górę, i do środka.
func _spiral_cells() -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	var x0 := 1; var y0 := 1; var x1 := cols - 2; var y1 := rows - 2
	while x0 <= x1 and y0 <= y1:
		for x in range(x0, x1 + 1): out.append(Vector2i(x, y0))
		for y in range(y0 + 1, y1 + 1): out.append(Vector2i(x1, y))
		if y1 > y0:
			for x in range(x1 - 1, x0 - 1, -1): out.append(Vector2i(x, y1))
		if x1 > x0:
			for y in range(y1 - 1, y0, -1): out.append(Vector2i(x0, y))
		x0 += 1; y0 += 1; x1 -= 1; y1 -= 1
	return out


func _drop_block(cell: Vector2i) -> void:
	if breakable_cells.has(cell):
		var box = breakable_cells[cell]
		breakable_cells.erase(cell)
		if is_instance_valid(box): box.queue_free()
	if powerup_cells.has(cell) and is_instance_valid(powerup_cells[cell]):
		powerup_cells[cell].queue_free()
	for bomb in get_tree().get_nodes_in_group("bomb"):
		if bomb.has_method("crush") and bomb.get_cell() == cell:
			bomb.crush()
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_alive and p.get_grid_pos() == cell:
			p.crush()
	solid_cells[cell] = true
	var px := Vector2(cell.x * GRID_SIZE, cell.y * GRID_SIZE)
	var block := _spawn_solid_block(get_node("Map"), px, COLOR_SOLID)
	block.scale = Vector2(1.5, 1.5)
	block.modulate.a = 0.0
	var tw := block.create_tween().set_parallel()
	tw.tween_property(block, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_IN)
	tw.tween_property(block, "modulate:a", 1.0, 0.1)


func _draw_sudden_warn() -> void:
	for c in sudden_death_danger():
		_sd_warn.draw_rect(Rect2(Vector2(c) * GRID_SIZE, Vector2(GRID_SIZE, GRID_SIZE)), COLOR_SUDDEN_WARN)
