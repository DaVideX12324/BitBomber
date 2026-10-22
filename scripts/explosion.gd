extends Area2D

## Eksplozja — płomień na jednym polu przez LIFETIME sekund.
## Przez cały ten czas rani graczy, niszczy power-upy i odpala bomby na swoim polu
## (reakcja łańcuchowa, także bomb położonych w płonący ogień).
## collision_layer = 0
## collision_mask  = 8  (hitboxy graczy i power-upów)

const LIFETIME: float = 0.5
## Do tego ułamka LIFETIME płomień jest pełny, potem gaśnie.
const FADE_START: float = 0.6
const GRID_SIZE: int = 64

@onready var _sprite  : Sprite2D  = $Sprite2D
@onready var _fallback: ColorRect = $Fallback

var _timer: float = 0.0
var _cell: Vector2i
## player_id właściciela bomby (0 = brak) — do liczenia zabójstw
var owner_id: int = 0
## Grafika: "center", "arm" albo "end" (ramię i koniec narysowane w prawo — bomba obraca węzeł)
var segment: String = "center"


func _ready() -> void:
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/explosion_%s.png" % segment)
	monitoring = true
	_cell = Vector2i(int(global_position.x / GRID_SIZE), int(global_position.y / GRID_SIZE))


func _process(delta: float) -> void:
	_timer += delta
	var t := _timer / LIFETIME
	modulate.a = 1.0 if t < FADE_START else 1.0 - (t - FADE_START) / (1.0 - FADE_START)
	if _timer >= LIFETIME:
		queue_free()


func _physics_process(_delta: float) -> void:
	for area in get_overlapping_areas():
		var stuff = area.get_parent()
		if stuff.has_method("take_hit"):
			stuff.take_hit(owner_id)
	for bomb in get_tree().get_nodes_in_group("bomb"):
		if bomb.has_method("detonate") and bomb.get_cell() == _cell:
			bomb.detonate()
