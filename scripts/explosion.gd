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
	collision_layer = 8
	collision_mask  = 2
	monitoring = true
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_timer += delta
	modulate.a = 1.0 - (_timer / LIFETIME)
	if _timer >= LIFETIME:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_hit"):
		body.take_hit()
