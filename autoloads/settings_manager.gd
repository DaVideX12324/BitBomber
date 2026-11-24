extends Node

## Autoload: wczytuje i zapisuje ustawienia wyświetlania.
## Jedyny właściciel pliku user://settings.cfg.
## Kontroluje pełny cykl życia UIScaleManager (init, reakcja na zmiany, zapis).

const CONFIG_PATH := "user://settings.cfg"
const SEC         := "display"
const SEC_AUDIO   := "audio"
const AUDIO_BUSES : Array[String] = ["Master", "Music", "SFX"]

## 0 = okienkowy, 1 = bez ramki, 2 = pełny ekran
var window_mode_idx : int      = 2
var resolution      : Vector2i = Vector2i(1920, 1080)
var monitor_idx     : int      = 0

signal resolution_changed(new_resolution: Vector2i)


func _ready() -> void:
	BbInput.ensure_actions()
	BbInput.load_saved()
	var cfg := _load()
	_load_audio(cfg)
	UIScaleManager.load_from_cfg(cfg)
	resolution_changed.connect(UIScaleManager.on_resolution_changed)
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

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	match mode_idx:
		0: # Okienkowy z ramką
			_disable_stretch()
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
		1: # Bez ramki
			_disable_stretch()
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			var clamped := Vector2i(
				mini(res.x, screen_size.x),
				mini(res.y, screen_size.y)
			)
			DisplayServer.window_set_size(clamped)
			DisplayServer.window_set_position(
				screen_pos + (screen_size - clamped) / 2
			)
		2: # Pełny ekran
			DisplayServer.window_set_size(res)
			DisplayServer.window_set_position(
				screen_pos + (screen_size - res) / 2
			)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_enable_stretch(res)

	_save()
	if res != prev_res:
		resolution_changed.emit(resolution)


# ---------------------------------------------------------------------------
# Stretch helpers
# ---------------------------------------------------------------------------

func _enable_stretch(render_res: Vector2i) -> void:
	var root := get_tree().root
	root.content_scale_size   = render_res
	root.content_scale_mode   = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _disable_stretch() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO


# ---------------------------------------------------------------------------

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
# Prywatne — jedyny punkt zapisu/odczytu settings.cfg
# ---------------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SEC, "window_mode_idx", window_mode_idx)
	cfg.set_value(SEC, "resolution_x",   resolution.x)
	cfg.set_value(SEC, "resolution_y",   resolution.y)
	cfg.set_value(SEC, "monitor_idx",    monitor_idx)
	UIScaleManager.save_to_cfg(cfg)
	cfg.save(CONFIG_PATH)


## Głośność szyn (Master / Music / SFX) z Opcji → Dźwięk.
func save_audio() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	for bus in AUDIO_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			cfg.set_value(SEC_AUDIO, bus, db_to_linear(AudioServer.get_bus_volume_db(idx)))
	cfg.save(CONFIG_PATH)


## Samodzielnie nie ma układu szyn hosta — Music i SFX tworzymy sami (wpięte w Master), żeby suwaki działały.
func _load_audio(cfg: ConfigFile) -> void:
	for bus in AUDIO_BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var new_idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(new_idx, bus)
			AudioServer.set_bus_send(new_idx, "Master")
	for bus in AUDIO_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0 and cfg.has_section_key(SEC_AUDIO, bus):
			AudioServer.set_bus_volume_db(idx, linear_to_db(float(cfg.get_value(SEC_AUDIO, bus))))


func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		var native := DisplayServer.screen_get_size(0)
		resolution      = native
		window_mode_idx = 2
		return cfg
	window_mode_idx = cfg.get_value(SEC, "window_mode_idx", 2)
	var rx : int = cfg.get_value(SEC, "resolution_x", DisplayServer.screen_get_size(0).x)
	var ry : int = cfg.get_value(SEC, "resolution_y", DisplayServer.screen_get_size(0).y)
	resolution  = Vector2i(rx, ry)
	monitor_idx = cfg.get_value(SEC, "monitor_idx", 0)
	return cfg
