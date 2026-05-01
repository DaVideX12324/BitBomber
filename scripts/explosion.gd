extends Area2D

## Eksplozja — krótki flash, zadaje obrażenia graczom i niszczy skrzynki.
## collision_mask = 3 (warstwa 1=ściany/skrzynki, warstwa 2=gracze)

const LIFETIME: float = 0.5

@onready var _sprite  : Sprite2D  = $Sprite2D
@onready var _fallback: ColorRect = $Fallback

var _timer: float = 0.0


func _ready() -> void:
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/explosion.png")
	# Warstwa 1 = mapa (bloki), warstwa 2 = gracze
	collision_mask = 3
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
	if body.is_in_group("breakable"):
		body.break_box()
