extends Node

## Autoload: wczytuje i zapisuje ustawienia wyświetlania.
## Ścieżka: user://settings.cfg

const CONFIG_PATH := "user://settings.cfg"
const SEC         := "display"

## 0 = okienkowy, 1 = bez ramki, 2 = pełny ekran
var window_mode_idx : int      = 0
var resolution      : Vector2i = Vector2i(1280, 720)
var monitor_idx     : int      = 0

signal resolution_changed(new_resolution: Vector2i)


func _ready() -> void:
	_load()
	monitor_idx = clampi(monitor_idx, 0, DisplayServer.get_screen_count() - 1)
	apply_settings(window_mode_idx, resolution, monitor_idx)


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func apply_settings(mode_idx: int, res: Vector2i, screen: int) -> void:
	var prev_res := resolution
	window_mode_idx = mode_idx
	resolution      = res
	monitor_idx     = clampi(screen, 0, DisplayServer.get_screen_count() - 1)

	var screen_pos  := DisplayServer.screen_get_position(monitor_idx)
	var screen_size := DisplayServer.screen_get_size(monitor_idx)

	# Zawsze najpierw wróć do czystego trybu okienkowego z ramką.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	match mode_idx:
		0: # Okienkowy z ramką
			# Pobierz grubość dekoracji (ramki) aby okno zewnętrzne mieściło się w res.
			# window_get_size_with_decorations() dostepne dopiero po ustawieniu rozmiaru,
			# więc najpierw ustaw żądany rozmiar, potem skompensuj.
			DisplayServer.window_set_size(res)
			var decorated := DisplayServer.window_get_size_with_decorations()
			var border    := decorated - DisplayServer.window_get_size()
			var inner     := Vector2i(
				maxi(res.x - border.x, 320),
				maxi(res.y - border.y, 240)
			)
			DisplayServer.window_set_size(inner)
			DisplayServer.window_set_position(
				screen_pos + (screen_size - decorated) / 2
			)
		1: # Bez ramki — dokładnie wypełnij obszar monitora bez wychodzenia poza niego
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var clamped := Vector2i(
				mini(res.x, screen_size.x),
				mini(res.y, screen_size.y)
			)
			DisplayServer.window_set_size(clamped)
			# Wycentruj w granicach monitora
			DisplayServer.window_set_position(
				screen_pos + (screen_size - clamped) / 2
			)
		2: # Pełny ekran (exclusive)
			DisplayServer.window_set_size(res)
			DisplayServer.window_set_position(
				screen_pos + (screen_size - res) / 2
			)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	_save()
	if res != prev_res:
		resolution_changed.emit(resolution)


func get_available_resolutions() -> Array[Vector2i]:
	var screen_size := DisplayServer.screen_get_size(monitor_idx)
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
	if not result.has(screen_size):
		result.append(screen_size)
	return result


# ---------------------------------------------------------------------------
# Prywatne
# ---------------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SEC, "window_mode_idx", window_mode_idx)
	cfg.set_value(SEC, "resolution_x", resolution.x)
	cfg.set_value(SEC, "resolution_y", resolution.y)
	cfg.set_value(SEC, "monitor_idx", monitor_idx)
	cfg.save(CONFIG_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	window_mode_idx = cfg.get_value(SEC, "window_mode_idx", 0)
	var rx : int = cfg.get_value(SEC, "resolution_x", 1280)
	var ry : int = cfg.get_value(SEC, "resolution_y", 720)
	resolution  = Vector2i(rx, ry)
	monitor_idx = cfg.get_value(SEC, "monitor_idx", 0)
