extends Node2D

## Bomba BitBomber — 64px grid, timer, eksplozja krzyżem.

const EXPLOSION_SCENE = preload("res://scenes/objects/explosion.tscn")
const GRID_SIZE: int = 64
const FUSE_TIME: float = 2.5

@export var explosion_range: int = 2
var owner_player: Node = null  # referencja do gracza (do odblokowania slotu bomby)

signal exploded

# Programmer art fallback
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _fallback: ColorRect = $Fallback

var _timer: float = 0.0


func _ready() -> void:
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/bomb.png")


func _process(delta: float) -> void:
	_timer += delta
	# Pulsowanie (programmer art)
	var scale_val = 1.0 + 0.1 * sin(_timer * TAU * 2.0)
	scale = Vector2(scale_val, scale_val)
	if _timer >= FUSE_TIME:
		_explode()


func _explode() -> void:
	set_process(false)
	exploded.emit()

	# Spawuj eksplozje w 4 kierunkach + środek
	var directions = [Vector2i.ZERO, Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir in directions:
		if dir == Vector2i.ZERO:
			_spawn_explosion(global_position)
			continue
		for i in range(1, explosion_range + 1):
			var offset = Vector2(dir.x * i * GRID_SIZE, dir.y * i * GRID_SIZE)
			# TODO: sprawdzić czy kafelek nie jest ścianą stałą (Arena.is_solid)
			_spawn_explosion(global_position + offset)

	queue_free()


func _spawn_explosion(pos: Vector2) -> void:
	var exp = EXPLOSION_SCENE.instantiate()
	exp.global_position = pos
	get_parent().add_child(exp)
