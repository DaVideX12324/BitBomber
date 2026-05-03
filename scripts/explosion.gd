extends Area2D

## Eksplozja — krótki flash, zadaje obrażenia graczom.
## collision_layer = 8  (eksplozje)
## collision_mask  = 2  (gracze)

const LIFETIME: float = 0.2

@onready var _sprite  : Sprite2D  = $Sprite2D
@onready var _fallback: ColorRect = $Fallback

var _timer: float = 0.0


func _ready() -> void:
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/explosion.png")
	monitoring = true


func _process(delta: float) -> void:
	_timer += delta
	modulate.a = 1.0 - (_timer / LIFETIME)
	if _timer >= LIFETIME:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	var stuff = area.get_parent()
	if stuff.has_method("take_hit"):
		stuff.take_hit()
	elif stuff.is_in_group("powerup"):
		stuff.queue_free()
