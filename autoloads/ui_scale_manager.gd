extends Node
## Autoload: UIScaleManager
##
## Zarządza trybem skalowania UI per-węzeł (font_size + custom_minimum_size).
##
## Tryb domyślny jest dobierany automatycznie na podstawie wybranej
## rozdzielczości (SettingsManager.resolution). Gdy gracz zmieni
## rozdzielczość i NIE ma ręcznego wyboru skali, skala aktualizuje się
## automatycznie. Jeśli gracz sam wybrał tryb — jego wybór zostaje,
## ale jest przycinany w dół jeśli ekran jest za mały.
##
## Zapis/odczyt delegowany do SettingsManager — ten plik nie dotyka settings.cfg.
##
## Progi (wysokość rozdzielczości):
##   XSMALL — 0.50×  (≤ 720px)
##   SMALL  — 0.75×  (≤ 900px)
##   NORMAL — 1.0×   (≤ 1080px)
##   LARGE  — 1.5×   (≤ 2159px)
##   XLARGE — 2.0×   (≥ 2160px)
##
## API:
##   UIScaleManager.px(base)           — int, przelicza rozmiar czcionki
##   UIScaleManager.sz(base)           — float, przelicza pojedynczy wymiar
##   UIScaleManager.sz2(w, h)          — Vector2, przelicza rozmiar 2D
##   UIScaleManager.set_mode(m)        — ręczny wybór (blokuje auto)
##   UIScaleManager.reset_to_auto()    — powrót do auto-detekcji
##   UIScaleManager.load_from_cfg(cfg) — wywoływane przez SettingsManager
##   UIScaleManager.save_to_cfg(cfg)   — wywoływane przez SettingsManager
##   UIScaleManager.scale_changed      — sygnał emitowany przy każdej zmianie

enum ScaleMode { XSMALL, SMALL, NORMAL, LARGE, XLARGE }

const SCALE_VALUES : Dictionary = {
	ScaleMode.XSMALL: 0.5,
	ScaleMode.SMALL:  0.75,
	ScaleMode.NORMAL: 1.0,
	ScaleMode.LARGE:  1.5,
	ScaleMode.XLARGE: 2.0,
}

const SCALE_LABELS : Dictionary = {
	ScaleMode.XSMALL: "B. Małe (0.5×)",
	ScaleMode.SMALL:  "Małe (0.75×)",
	ScaleMode.NORMAL: "Normalne (1×)",
	ScaleMode.LARGE:  "Duże (1.5×)",
	ScaleMode.XLARGE: "4K (2×)",
}

const MIN_SCREEN_H : Dictionary = {
	ScaleMode.XLARGE: 2160,
	ScaleMode.LARGE:  1081,
	ScaleMode.NORMAL:  901,
	ScaleMode.SMALL:   721,
	ScaleMode.XSMALL:    0,
}

var current_mode : ScaleMode = ScaleMode.NORMAL :
	set(value):
		current_mode = value
		scale_factor = SCALE_VALUES[value]
		scale_changed.emit(scale_factor)

var scale_factor : float = 1.0

## true = gracz sam wybrał tryb; false = tryb dobierany automatycznie
var _user_picked : bool = false

signal scale_changed(new_scale: float)


func _ready() -> void:
	# Dane wczytuje SettingsManager — tutaj tylko podłączamy sygnał.
	SettingsManager.resolution_changed.connect(_on_resolution_changed)


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

## Ręczny wybór trybu przez gracza — blokuje auto-detekcję.
## SettingsManager zadba o zapis przy najbliższym apply_settings().
func set_mode(mode: ScaleMode) -> void:
	_user_picked = true
	current_mode = _clamp_mode_to_screen(mode)


## Powrót do auto-detekcji na podstawie rozdzielczości.
func reset_to_auto() -> void:
	_user_picked = false
	current_mode = _detect_mode()


func get_mode_labels() -> Array[String]:
	return [
		SCALE_LABELS[ScaleMode.XSMALL],
		SCALE_LABELS[ScaleMode.SMALL],
		SCALE_LABELS[ScaleMode.NORMAL],
		SCALE_LABELS[ScaleMode.LARGE],
		SCALE_LABELS[ScaleMode.XLARGE],
	]


func px(base_pixels: float) -> int:
	return roundi(base_pixels * scale_factor)


func sz(base: float) -> float:
	return base * scale_factor


func sz2(w: float, h: float) -> Vector2:
	return Vector2(w, h) * scale_factor


# ---------------------------------------------------------------------------
# I/O delegowane do SettingsManager
# ---------------------------------------------------------------------------

func load_from_cfg(cfg: ConfigFile) -> void:
	var is_auto : bool = cfg.get_value("ui", "ui_scale_auto", true)
	if not is_auto:
		var saved : int = cfg.get_value("ui", "ui_scale_mode", -1)
		if saved >= ScaleMode.XSMALL and saved <= ScaleMode.XLARGE:
			_user_picked = true
			current_mode = _clamp_mode_to_screen(saved as ScaleMode)
			return
	_user_picked = false
	current_mode = _detect_mode()


func save_to_cfg(cfg: ConfigFile) -> void:
	cfg.set_value("ui", "ui_scale_mode", current_mode)
	cfg.set_value("ui", "ui_scale_auto", not _user_picked)


# ---------------------------------------------------------------------------
# Reakcja na zmianę rozdzielczości
# ---------------------------------------------------------------------------

func _on_resolution_changed(_new_res: Vector2i) -> void:
	if _user_picked:
		current_mode = _clamp_mode_to_screen(current_mode)
		return
	current_mode = _detect_mode()


# ---------------------------------------------------------------------------
# Detekcja i clamp
# ---------------------------------------------------------------------------

func _detect_mode() -> ScaleMode:
	var y : int = SettingsManager.resolution.y
	if y <= 0:
		y = DisplayServer.window_get_size().y
	if   y >= 2160: return ScaleMode.XLARGE
	elif y > 1080:  return ScaleMode.LARGE
	elif y > 900:   return ScaleMode.NORMAL
	elif y > 720:   return ScaleMode.SMALL
	else:           return ScaleMode.XSMALL


func _clamp_mode_to_screen(mode: ScaleMode) -> ScaleMode:
	var h : int = SettingsManager.resolution.y
	if h <= 0:
		h = DisplayServer.window_get_size().y
	while mode > ScaleMode.XSMALL and h < MIN_SCREEN_H[mode]:
		mode = (mode - 1) as ScaleMode
	return mode
