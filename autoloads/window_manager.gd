extends Node

## Centruje okno gry na monitorze, na którym aktualnie znajduje się kursor.
## Działa tylko w trybie Desktop.

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame  # poczekaj aż okno dostanie rozmiar
		_center_on_cursor_screen()


func _center_on_cursor_screen() -> void:
	var cursor_pos  : Vector2i = DisplayServer.mouse_get_position()
	var screen_idx  : int      = _get_screen_at(cursor_pos)
	var screen_pos  : Vector2i = DisplayServer.screen_get_position(screen_idx)
	var screen_size : Vector2i = DisplayServer.screen_get_size(screen_idx)
	var window_size : Vector2i = DisplayServer.window_get_size()
	var centered    : Vector2i = screen_pos + (screen_size - window_size) / 2
	DisplayServer.window_set_position(centered)


## Zwraca indeks monitora, na którym leży punkt `pos` (wsp. globalne).
## Jeśli punkt nie leży na żadnym monitorze, zwraca ekran główny.
func _get_screen_at(pos: Vector2i) -> int:
	var count : int = DisplayServer.get_screen_count()
	for i in count:
		var s_pos  : Vector2i = DisplayServer.screen_get_position(i)
		var s_size : Vector2i = DisplayServer.screen_get_size(i)
		var rect   := Rect2i(s_pos, s_size)
		if rect.has_point(pos):
			return i
	return DisplayServer.get_primary_screen()
