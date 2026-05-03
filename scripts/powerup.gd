extends Sprite2D

## Power-up leżący na planszy.
## Typy: range_up, bomb_up, speed_up, life_up

const GRID_SIZE : int = 64

const COLORS : Dictionary = {
	"range_up":  Color(1.0, 0.8, 0.1),
	"bomb_up":   Color(1.0, 0.4, 0.1),
	"speed_up":  Color(0.2, 0.9, 0.4),
	"life_up":   Color(1.0, 0.2, 0.4),
}

const ICONS : Dictionary = {
	"range_up":  "🏹",
	"bomb_up":   "🧨",
	"speed_up":  "👟",
	"life_up":   "♥",
}

var powerup_type : String = "range_up"

@onready var _fallback : ColorRect        = $Fallback
@onready var _label    : Label            = $Label
@onready var _sprite   : Sprite2D         = $Sprite2D
@onready var Hitbox    : CollisionShape2D =$Hitbox/CollisionShape2D

signal collected(powerup_type: String)


func _ready() -> void:
	var col : Color = COLORS.get(powerup_type, Color.WHITE)
	_fallback.color = col
	var icon : String = ICONS.get(powerup_type, "?")
	_label.text = icon
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/powerup_%s.png" % powerup_type)
	_bob()
	Hitbox.disabled = 1
	await get_tree().create_timer(0.21).timeout
	Hitbox.disabled = 0

func _bob() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position:y", position.y - 5, 0.6).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position:y", position.y,     0.6).set_ease(Tween.EASE_IN_OUT)


func _on_hitbox_area_entered(area: Area2D) -> void:	
	var stuff = area.get_parent()
	if stuff.has_method("apply_powerup"):
		stuff.apply_powerup(powerup_type)
		collected.emit(powerup_type)
		queue_free()

func take_hit() -> void:
	queue_free()
