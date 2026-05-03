extends StaticBody2D

const EXPLOSION_SCENE = preload("res://scenes/objects/explosion.tscn")
const GRID_SIZE : int   = 64
const FUSE_TIME : float = 2

@export var explosion_range : int  = 1
var owner_player            : Node = null

signal exploded

@onready var _sprite   : Sprite2D  = $Sprite2D
@onready var _fallback : ColorRect = $Fallback

var _timer : float = 0.0


func _ready() -> void:
	add_to_group("bomb")
	collision_layer = 4
	collision_mask  = 0
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/bomb.png")


func _process(delta: float) -> void:
	_timer += delta
	var scale_val := 1.0 + 0.1 * sin(_timer * TAU * 2.0)
	scale = Vector2(scale_val, scale_val)
	if _timer >= FUSE_TIME:
		_explode()


## Czas pozostały do wybuchu — używane przez bot_ai.gd
func time_left() -> float:
	return maxf(FUSE_TIME - _timer, 0.0)


func _explode() -> void:
	set_process(false)
	exploded.emit()

	var arena  : Node     = _get_arena()
	var origin : Vector2i = _pixel_to_grid(global_position)

	_spawn_explosion(global_position)

	var directions : Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir : Vector2i in directions:
		for i : int in range(1, explosion_range):
			var cell : Vector2i = origin + dir * i
			var pos  : Vector2  = _grid_to_pixel(cell)

			if arena and arena.is_solid(cell):
				break

			if arena and arena.is_breakable(cell):
				_spawn_explosion(pos)
				arena.break_cell(cell)
				break

			_spawn_explosion(pos)

	queue_free()


func _spawn_explosion(pos: Vector2) -> void:
	var exp := EXPLOSION_SCENE.instantiate()
	exp.global_position = pos
	var target := _get_map_root()
	target.add_child(exp)


func _get_arena() -> Node:
	var node := get_parent() as Node
	while node:
		if node.has_method("is_solid"):
			return node
		node = node.get_parent()
	return null


func _get_map_root() -> Node:
	var gn := GameManager.game_node
	if gn and gn.get("_current_map") != null:
		return gn._current_map
	return get_parent()


func _pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


func _grid_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID_SIZE + GRID_SIZE / 2, cell.y * GRID_SIZE + GRID_SIZE / 2)
