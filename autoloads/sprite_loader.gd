extends Node

## SpriteLoader — ładuje tekstury jeśli istnieją, w przeciwnym razie zwraca null.
## Sceny używają tego do przełączania między teksturą a programmer art (ColorRect).
##
## Konwencja ścieżek tekstur:
##   res://assets/sprites/<kategoria>/<nazwa>.png
## Przykłady:
##   res://assets/sprites/players/player_1.png
##   res://assets/sprites/players/player_2.png
##   res://assets/sprites/objects/bomb.png
##   res://assets/sprites/objects/explosion.png
##   res://assets/sprites/map/wall_solid.png
##   res://assets/sprites/map/wall_breakable.png
##   res://assets/sprites/map/powerup_quiz.png

const SPRITES_BASE = "res://assets/sprites/"

## Zwraca Texture2D jeśli plik istnieje, null jeśli nie.
func get_texture(relative_path: String) -> Texture2D:
	var full_path = SPRITES_BASE + relative_path
	if ResourceLoader.exists(full_path):
		return load(full_path) as Texture2D
	return null


## Ustawia teksturę na Sprite2D jeśli dostępna.
## Jeśli nie — ukrywa sprite i pokazuje fallback_node (ColorRect).
## Zwraca true jeśli tekstura została ustawiona.
func apply_or_fallback(sprite: Sprite2D, fallback_node: Node, relative_path: String) -> bool:
	var tex = get_texture(relative_path)
	if tex:
		sprite.texture = tex
		sprite.visible = true
		fallback_node.visible = false
		return true
	else:
		sprite.visible = false
		fallback_node.visible = true
		return false
