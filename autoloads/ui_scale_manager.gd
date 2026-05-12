extends Node
## Autoload: UIScaleManager
##
## Zarządza trybem skalowania UI per-węzeł (font_size + custom_minimum_size).
##
## Tryb domyślny jest dobierany automatycznie na podstawie wybranej
## rozdzielczości (SettingsManager.resolution). Gdy gracz zmieni
## rozdzielczość i NIE ma ręcznego wyboru skali, skala aktualizuje się
## automatycznie. Jeśli gracz sam wybrał tryb — jego wybór zostaje.
##
## Progi (szerokość rozdzielczości):
##   SMALL  — 0.75×  (< 1280px)
##   NORMAL — 1.0×   (1280–1919px)
##   LARGE  — 1.5×   (1920–2559px)
##   XLARGE — 2.0×   (≥ 2560px)
##
## API:
##   UIScaleManager.px(base)      — int, przelicza rozmiar czcionki
##   UIScaleManager.sz(base)      — float, przelicza pojedynczy wymiar
##   UIScaleManager.sz2(w, h)     — Vector2, przelicza rozmiar 2D
##   UIScaleManager.set_mode(m)   — ręczny wybór + zapis (blokuje auto)
##   UIScaleManager.scale_changed — sygnał emitowany przy każdej zmianie

enum ScaleMode { XSMALL, SMALL, NORMAL, LARGE, XLARGE }

const SCALE_VALUES : Dictionary = {
	ScaleMode.XSMALL: 0.6,
	ScaleMode.SMALL:  0.75,
	ScaleMode.NORMAL: 1.0,
	ScaleMode.LARGE:  1.5,
	ScaleMode.XLARGE: 2.0,
}

const SCALE_LABELS : Dictionary = {
	ScaleMode.XSMALL:  "B. Małe (0.6×)",
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

## true = gracz sam wybrał tryb; false = tryb dobierany automatycznie
var _user_picked : bool = false

signal scale_changed(new_scale: float)


func _ready() -> void:
	_load_saved()
	# Po załadowaniu ustawień podłącz się do sygnału rozdzielczości
	SettingsManager.resolution_changed.connect(_on_resolution_changed)


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

## Ręczny wybór trybu przez gracza — blokuje auto-detekcję i zapisuje.
func set_mode(mode: ScaleMode) -> void:
	_user_picked = true
	current_mode = mode
	_save()


## Czyści ręczny wybór — od tej pory skala zmienia się wraz z rozdzielczością.
func reset_to_auto() -> void:
	_user_picked = false
	_save_user_picked()
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
# Reakcja na zmianę rozdzielczości
# ---------------------------------------------------------------------------

func _on_resolution_changed(_new_res: Vector2i) -> void:
	if _user_picked:
		return  # gracz ma ręczny wybór — nie nadpisuj
	current_mode = _detect_mode()


# ---------------------------------------------------------------------------
# Detekcja na podstawie wybranej rozdzielczości
# ---------------------------------------------------------------------------

func _detect_mode() -> ScaleMode:
	var y : int = SettingsManager.resolution.y
	if y <= 0:
		y = DisplayServer.window_get_size().y
	if   y >= 2160: return ScaleMode.XLARGE
	elif y > 1080: return ScaleMode.LARGE
	elif y > 900: return ScaleMode.NORMAL
	elif y > 720: return ScaleMode.SMALL
	else:           return ScaleMode.XSMALL


# ---------------------------------------------------------------------------
# Zapis / odczyt
# ---------------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")  # zachowaj istniejące klucze
	cfg.set_value("ui", SAVE_KEY, current_mode)
	cfg.set_value("ui", "ui_scale_auto", not _user_picked)
	cfg.save("user://settings.cfg")


func _save_user_picked() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("ui", "ui_scale_auto", true)
	cfg.save("user://settings.cfg")


func _load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var is_auto : bool = cfg.get_value("ui", "ui_scale_auto", true)
		if not is_auto:
			var saved : int = cfg.get_value("ui", SAVE_KEY, -1)
			if saved >= 0 and saved <= ScaleMode.XLARGE:
				_user_picked = true
				current_mode = saved as ScaleMode
				return
	current_mode = _detect_mode()
