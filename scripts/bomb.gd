extends Node2D

const EXPLOSION_SCENE = preload("res://scenes/objects/explosion.tscn")
const GRID_SIZE : int   = 64
const FUSE_TIME : float = 2.5

@export var explosion_range : int  = 2
var owner_player            : Node = null

signal exploded

@onready var _sprite   : Sprite2D  = $Sprite2D
@onready var _fallback : ColorRect = $Fallback

var _timer : float = 0.0


func _ready() -> void:
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/bomb.png")


func _process(delta: float) -> void:
	_timer += delta
	var scale_val = 1.0 + 0.1 * sin(_timer * TAU * 2.0)
	scale = Vector2(scale_val, scale_val)
	if _timer >= FUSE_TIME:
		_explode()


func _explode() -> void:
	set_process(false)
	exploded.emit()

	var arena = _get_arena()
	var origin = _pixel_to_grid(global_position)

	# środek zawsze
	_spawn_explosion(global_position)

	# 4 kierunki
	var directions = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir in directions:
		for i in range(1, explosion_range + 1):
			var cell = origin + dir * i
			var pos  = _grid_to_pixel(cell)

			if arena and arena.is_solid(cell):
				# Niezniszczalny — zatrzymaj, nie spawuj
				break

			if arena and arena.is_breakable(cell):
				# Zniszczalny — spawuj eksplozję na tym kafelku, zniszcz, zatrzymaj
				_spawn_explosion(pos)
				arena.break_cell(cell)
				break

			# Wolne pole
			_spawn_explosion(pos)

	queue_free()


func _spawn_explosion(pos: Vector2) -> void:
	var exp = EXPLOSION_SCENE.instantiate()
	exp.global_position = pos
	get_parent().add_child(exp)


func _get_arena() -> Node:
	# Hierarchia: Bomb -> Arena (lub Arena/Players/...)
	var node = get_parent()
	while node:
		if node.has_method("is_solid"):
			return node
		node = node.get_parent()
	return null


func _pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


func _grid_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID_SIZE + GRID_SIZE / 2, cell.y * GRID_SIZE + GRID_SIZE / 2)
