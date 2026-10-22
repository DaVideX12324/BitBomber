extends StaticBody2D

const BBRuntime = preload("bb_runtime.gd")
const BbSfx = preload("bb_sfx.gd")

var _explosion_scene: PackedScene = load(BBRuntime.path("scenes/objects/explosion.tscn"))
const GRID_SIZE : int   = 64
const FUSE_TIME : float = 2.0

@export var explosion_range : int  = 1
var owner_player            : Node = null

signal exploded

@onready var _sprite   : Sprite2D  = $Sprite2D
@onready var _fallback : ColorRect = $Fallback
@onready var _fuse_mat : ShaderMaterial = $Sprite2D.material

var _timer : float = 0.0
var _exploded : bool = false

## Kopnięcie (Bomb It: BombShoesProp): sunie z tą prędkością pole po polu, aż następne będzie zajęte.
const KICK_SPEED : float = 480.0
var _kick_dir    : Vector2i = Vector2i.ZERO
var _kick_target : Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("bomb")
	collision_layer = 4
	collision_mask  = 0
	
	if has_node("/root/SpriteLoader"):
		SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/bomb.png")
	
	# Zapisujemy materiał Sprite2D
	_fuse_mat = _sprite.material as ShaderMaterial
	
	_fallback.pivot_offset = _fallback.size / 2.0


func _process(delta: float) -> void:
	_timer += delta
	var scale_val := 1.0 + 0.1 * sin(_timer * TAU * 2.0)
	
	var progress: float = clampf(_timer / FUSE_TIME, 0.0, 1.0)
	
	# Aktualizacja shadera dla tekstury (jeśli istnieje)
	if _fuse_mat:
		_fuse_mat.set_shader_parameter("progress", progress)
		
	# Aktualizacja shadera dla Fallback (jeśli jest widoczny)
	if _fallback.visible and _fallback.material:
		(_fallback.material as ShaderMaterial).set_shader_parameter("progress", progress)
	
	var new_scale = Vector2(scale_val, scale_val)
	_sprite.scale = new_scale
	_fallback.scale = new_scale
	
	if _timer >= FUSE_TIME:
		_explode()


## Czas pozostały do wybuchu — używane przez bot_ai.gd do omijania bomb
func time_left() -> float:
	return maxf(FUSE_TIME - _timer, 0.0)


func get_cell() -> Vector2i:
	return _pixel_to_grid(global_position)


func is_sliding() -> bool:
	return _kick_dir != Vector2i.ZERO


## Kopnięcie w kierunku dir; false, gdy następne pole jest zajęte albo bomba już sunie.
func kick(dir: Vector2i) -> bool:
	if _exploded or is_sliding() or not _cell_free(get_cell() + dir):
		return false
	_kick_dir = dir
	_kick_target = _grid_to_pixel(get_cell() + dir)
	return true


func _physics_process(delta: float) -> void:
	if not is_sliding():
		return
	global_position = global_position.move_toward(_kick_target, KICK_SPEED * delta)
	if global_position.is_equal_approx(_kick_target):
		var next := get_cell() + _kick_dir
		if _cell_free(next):
			_kick_target = _grid_to_pixel(next)
		else:
			_kick_dir = Vector2i.ZERO


## Wolne dla sunącej bomby: bez ściany, skrzynki, innej bomby i żywego gracza.
func _cell_free(cell: Vector2i) -> bool:
	var arena := _get_arena()
	if arena and (arena.is_solid(cell) or arena.is_breakable(cell)):
		return false
	for b in get_tree().get_nodes_in_group("bomb"):
		if b != self and b.get_cell() == cell:
			return false
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_alive and p.get_grid_pos() == cell:
			return false
	return true


## Wybuch od razu — ogień innej bomby (reakcja łańcuchowa).
func detonate() -> void:
	_explode()


## Nagła śmierć: spada na nią blok — znika bez wybuchu (licznik bomb właściciela wraca).
func crush() -> void:
	if _exploded:
		return
	_exploded = true
	exploded.emit()
	queue_free()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	set_process(false)
	if is_sliding():
		# Wybuch w biegu — na polu, nad którym bomba właśnie jest.
		_kick_dir = Vector2i.ZERO
		global_position = _grid_to_pixel(get_cell())
	exploded.emit()
	BbSfx.play("explosion", -2.0, 0.1)

	var arena  : Node     = _get_arena()
	var origin : Vector2i = _pixel_to_grid(global_position)

	var cells : Array[Vector2i] = [origin]
	if arena and arena.has_method("blast_cells"):
		cells = arena.blast_cells(origin, explosion_range)
	for cell : Vector2i in cells:
		_spawn_explosion(_grid_to_pixel(cell), _segment_of(cell, origin, cells))
		if arena and arena.is_breakable(cell):
			arena.break_cell(cell)

	queue_free()


## [nazwa segmentu, obrót]: środek, ramię albo koniec ramienia (ostatnie pole w tym kierunku).
func _segment_of(cell: Vector2i, origin: Vector2i, cells: Array[Vector2i]) -> Array:
	if cell == origin:
		return ["center", 0.0]
	var dir := Vector2i(signi(cell.x - origin.x), signi(cell.y - origin.y))
	var angle := Vector2(dir).angle()
	return ["arm" if cells.has(cell + dir) else "end", angle]


func _spawn_explosion(pos: Vector2, seg: Array = ["center", 0.0]) -> void:
	var exp := _explosion_scene.instantiate()
	exp.global_position = pos
	exp.segment  = seg[0]
	exp.rotation = seg[1]
	exp.owner_id = int(owner_player.player_id) if is_instance_valid(owner_player) else 0
	var target := _get_map_root()
	if target:
		target.add_child(exp)


func _get_arena() -> Node:
	var node := get_parent() as Node
	while node:
		if node.has_method("is_solid"):
			return node
		node = node.get_parent()
	return null


func _get_map_root() -> Node:
	# Bezpieczne odpytanie Singletonu GameManager
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.get("game_node") != null:
		var gn = gm.game_node
		if gn and gn.get("_current_map") != null:
			return gn._current_map
	return get_parent()


func _pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


func _grid_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID_SIZE + GRID_SIZE / 2.0, cell.y * GRID_SIZE + GRID_SIZE / 2.0)
