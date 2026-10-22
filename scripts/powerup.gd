extends Sprite2D

## Power-up leżący na planszy.
## Typy: range_up, bomb_up, speed_up, life_up, kick, shield, star

const GRID_SIZE : int = 64

const COLORS : Dictionary = {
	"range_up":  Color(1.0, 0.8, 0.1),
	"bomb_up":   Color(1.0, 0.4, 0.1),
	"speed_up":  Color(0.2, 0.9, 0.4),
	"life_up":   Color(1.0, 0.2, 0.4),
	"kick":      Color(0.3, 0.6, 1.0),
	"shield":    Color(0.6, 0.85, 1.0),
	"star":      Color(1.0, 0.95, 0.4),
}

const ICONS : Dictionary = {
	"range_up":  "🏹",
	"bomb_up":   "🧨",
	"speed_up":  "👟",
	"life_up":   "♥",
	"kick":      "🦶",
	"shield":    "🛡",
	"star":      "⭐",
}

var powerup_type : String = "range_up"
var _age : float = 0.0

## Dłużej niż płomień (Explosion.LIFETIME = 0,5 s).
const SPAWN_FIRE_GRACE : float = 0.6

@onready var _fallback : ColorRect        = $Fallback
@onready var _label    : Label            = $Label
@onready var _sprite   : Sprite2D         = $Sprite2D

func _ready() -> void:
	var col : Color = COLORS.get(powerup_type, Color.WHITE)
	_fallback.color = col
	var icon : String = ICONS.get(powerup_type, "?")
	_label.text = icon
	_label.visible = not SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/powerup_%s.png" % powerup_type)
	_bob()

func _process(delta: float) -> void:
	_age += delta


func _bob() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position:y", position.y - 5, 0.6).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position:y", position.y,     0.6).set_ease(Tween.EASE_IN_OUT)


func _on_hitbox_area_entered(area: Area2D) -> void:	
	var stuff = area.get_parent()
	if stuff.has_method("apply_powerup") and stuff.is_alive:
		stuff.apply_powerup(powerup_type)
		queue_free()

## Ogień, który odsłonił power-up (skrzynka pod nim), jeszcze płonie — ten go nie niszczy.
func take_hit(_attacker_id: int = 0) -> void:
	if _age < SPAWN_FIRE_GRACE:
		return
	queue_free()
