extends Node

## Autoload: wczytuje i zapisuje ustawienia wyświetlania.
## Ścieżka: user://settings.cfg

const CONFIG_PATH := "user://settings.cfg"
const SEC         := "display"

## 0 = okienkowy, 1 = bez ramki, 2 = pełny ekran
var window_mode_idx : int      = 0
var resolution      : Vector2i = Vector2i(1280, 720)
var monitor_idx     : int      = 0

## Emitowany po każdej zmianie rozdzielczości (także przy starcie).
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
	# To zdejmuje zarówno flagę BORDERLESS jak i fullscreen —
	# bez tego zmiana z bezramkowego na okienkowy nie działa za pierwszym razem.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	# Dopiero teraz ustaw rozmiar i pozycję
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_position(
		screen_pos + (screen_size - res) / 2
	)

	match mode_idx:
		1: # Bez ramki
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2: # Pełny ekran (exclusive)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		# 0: okienkowy z ramką — już ustawiony powyżej, nic więcej

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
