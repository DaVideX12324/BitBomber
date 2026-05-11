extends Node

## Autoload: wczytuje i zapisuje ustawienia wyświetlania.
## Ścieżka: user://settings.cfg
##
## Użycie:
##   SettingsManager.apply_window_mode(mode)
##   SettingsManager.apply_resolution(Vector2i(1920, 1080))

const CONFIG_PATH := "user://settings.cfg"
const SEC := "display"

var window_mode : int     = DisplayServer.WINDOW_MODE_WINDOWED
var resolution  : Vector2i = Vector2i(1280, 720)


func _ready() -> void:
	_load()
	apply_window_mode(window_mode)
	apply_resolution(resolution)


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func apply_window_mode(mode: int) -> void:
	window_mode = mode
	DisplayServer.window_set_mode(mode)
	# W pełnym ekranie rozdzielczość ustawia się automatycznie przez OS
	if mode == DisplayServer.WINDOW_MODE_WINDOWED or mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		apply_resolution(resolution)
	_save()


func apply_resolution(res: Vector2i) -> void:
	resolution = res
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(res)
		_center_window()
	_save()


func get_available_resolutions() -> Array[Vector2i]:
	var screen_size := DisplayServer.screen_get_size()
	var candidates : Array[Vector2i] = [
		Vector2i(640,  480),
		Vector2i(800,  600),
		Vector2i(1024, 600),
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160),
	]
	var result : Array[Vector2i] = []
	for r in candidates:
		if r.x <= screen_size.x and r.y <= screen_size.y:
			result.append(r)
	# Dodaj natywną rozdzielczość monitora jeśli nie ma jej na liście
	if not result.has(screen_size):
		result.append(screen_size)
	return result


# ---------------------------------------------------------------------------
# Prywatne
# ---------------------------------------------------------------------------

func _center_window() -> void:
	var screen_size := DisplayServer.screen_get_size()
	var win_size    := DisplayServer.window_get_size()
	var pos := Vector2i(
		(screen_size.x - win_size.x) / 2,
		(screen_size.y - win_size.y) / 2
	)
	DisplayServer.window_set_position(pos)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SEC, "window_mode", window_mode)
	cfg.set_value(SEC, "resolution_x", resolution.x)
	cfg.set_value(SEC, "resolution_y", resolution.y)
	cfg.save(CONFIG_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	window_mode = cfg.get_value(SEC, "window_mode", DisplayServer.WINDOW_MODE_WINDOWED)
	var rx : int = cfg.get_value(SEC, "resolution_x", 1280)
	var ry : int = cfg.get_value(SEC, "resolution_y", 720)
	resolution = Vector2i(rx, ry)
