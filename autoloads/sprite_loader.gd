extends Node

## SpriteLoader — ładuje tekstury jeśli istnieją, w przeciwnym razie zwraca null.
## Sceny używają tego do przełączania między teksturą a programmer art (ColorRect).
##
## Grafika modułu: resources/sprites/<kategoria>/<nazwa>.png (generuje tools/gen_sprites.py), np.
##   players/player_1.png       — arkusz 3×4 klatki
##   objects/bomb.png, objects/explosion_center.png, objects/powerup_kick.png
##   tiles/forest/floor.png     — kafle motywu mapy

const BBRuntime = preload("../scripts/bb_runtime.gd")

var sprites_base : String = BBRuntime.path("resources/sprites/")

## Zwraca Texture2D jeśli plik istnieje, null jeśli nie.
func get_texture(relative_path: String) -> Texture2D:
	var full_path = sprites_base + relative_path
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
