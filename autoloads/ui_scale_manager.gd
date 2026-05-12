extends Node
## Autoload: UIScaleManager
##
## Zarządza trybem skalowania UI per-węzeł (font_size + custom_minimum_size).
##
## Tryb domyślny przy pierwszym uruchomieniu jest dobierany
## na podstawie WYBRANEJ ROZDZIELCZOŚCI w SettingsManager (nie rozmiaru monitora).
## Progi:
##   SMALL  — 0.75×  (szerokość < 1280px)
##   NORMAL — 1.0×   (1280–1919px)
##   LARGE  — 1.5×   (1920–2559px)
##   XLARGE — 2.0×   (≥ 2560px)
##
## API:
##   UIScaleManager.px(base)        — int, przelicza rozmiar czcionki
##   UIScaleManager.sz(base)        — float, przelicza pojedynczy wymiar
##   UIScaleManager.sz2(w, h)       — Vector2, przelicza rozmiar 2D
##   UIScaleManager.scale_changed   — sygnał emitowany przy zmianie trybu
##
## Użycie w _ready():
##   UIScaleManager.scale_changed.connect(_on_scale_changed)
##   _on_scale_changed(UIScaleManager.scale_factor)

enum ScaleMode { SMALL, NORMAL, LARGE, XLARGE }

const SCALE_VALUES : Dictionary = {
	ScaleMode.SMALL:  0.75,
	ScaleMode.NORMAL: 1.0,
	ScaleMode.LARGE:  1.5,
	ScaleMode.XLARGE: 2.0,
}

const SCALE_LABELS : Dictionary = {
	ScaleMode.SMALL:  "Małe (0.75×)",
	ScaleMode.NORMAL: "Normalne (1×)",
	ScaleMode.LARGE:  "Duże (1.5×)",
	ScaleMode.XLARGE: "4K (2×)",
}

const SAVE_KEY := "ui_scale_mode"

var current_mode : ScaleMode = ScaleMode.NORMAL :
	set(value):
		current_mode = value
		scale_factor = SCALE_VALUES[value]
		scale_changed.emit(scale_factor)

var scale_factor : float = 1.0

signal scale_changed(new_scale: float)


func _ready() -> void:
	_load_saved()


## Ustawia tryb ręcznie i zapisuje wybór gracza.
func set_mode(mode: ScaleMode) -> void:
	current_mode = mode
	_save()


## Zwraca listę etykiet wszystkich trybów (do OptionButton).
func get_mode_labels() -> Array[String]:
	return [
		SCALE_LABELS[ScaleMode.SMALL],
		SCALE_LABELS[ScaleMode.NORMAL],
		SCALE_LABELS[ScaleMode.LARGE],
		SCALE_LABELS[ScaleMode.XLARGE],
	]


## Przelicza rozmiar czcionki z bazy 1080p.
func px(base_pixels: float) -> int:
	return roundi(base_pixels * scale_factor)


## Przelicza pojedynczy wymiar (margin, separation itp.).
func sz(base: float) -> float:
	return base * scale_factor


## Przelicza rozmiar 2D (custom_minimum_size, offset itp.).
func sz2(w: float, h: float) -> Vector2:
	return Vector2(w, h) * scale_factor


# ---------------------------------------------------------------------------
# Zapis / odczyt
# ---------------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", SAVE_KEY, current_mode)
	cfg.save("user://settings.cfg")


func _load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var saved : int = cfg.get_value("ui", SAVE_KEY, -1)
		if saved >= 0 and saved <= ScaleMode.XLARGE:
			current_mode = saved as ScaleMode
			return
	# Brak zapisu — dobierz tryb na podstawie wybranej rozdzielczości
	current_mode = _detect_mode()


## Dobiera tryb na podstawie szerokości rozdzielczości z SettingsManager.
## Fallback: rozmiar aktualnego okna (gdy SettingsManager jeszcze nie gotowy).
func _detect_mode() -> ScaleMode:
	var w : int = 0
	if Engine.has_singleton("SettingsManager"):
		w = SettingsManager.resolution.x
	if w <= 0:
		w = DisplayServer.window_get_size().x
	if   w >= 2560: return ScaleMode.XLARGE
	elif w >= 1920: return ScaleMode.LARGE
	elif w >= 1280: return ScaleMode.NORMAL
	else:           return ScaleMode.SMALL
