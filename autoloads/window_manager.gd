extends Node

## Centruje okno gry na ekranie przy starcie.
## Działa tylko w trybie Desktop (nie HTML5, nie mobile).

func _ready() -> void:
	if not DisplayServer.get_name() == "headless":
		_center_window()


func _center_window() -> void:
	await get_tree().process_frame  # poczekaj aż okno dostanie rozmiar
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var centered: Vector2i = (screen_size - window_size) / 2
	DisplayServer.window_set_position(centered)
