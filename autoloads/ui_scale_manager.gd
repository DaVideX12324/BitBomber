extends Node
## Autoload: UIScaleManager
##
## Zarządza ręcznym trybem skalowania UI.
## Nie skaluje viewportu — zamiast tego emituje scale_changed,
## a każdy skrypt UI sam aplikuje rozmiary przez px().
##
## Tryby:
##   SMALL  — 0.75× (małe okno / tablet)
##   NORMAL — 1.0×  (domyślne, baza FHD 1080p)
##   LARGE  — 1.5×  (duży monitor 1440p)
##   XLARGE — 2.0×  (4K / wysoki DPI)
##
## Użycie w skrypcie UI:
##   func _ready():
##       UIScaleManager.scale_changed.connect(_on_scale_changed)
##       _on_scale_changed(UIScaleManager.scale_factor)
##
##   func _on_scale_changed(s: float) -> void:
##       $Label.add_theme_font_size_override("font_size", UIScaleManager.px(32))

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

## Aktualny tryb skalowania
var current_mode : ScaleMode = ScaleMode.NORMAL :
	set(value):
		current_mode = value
		scale_factor = SCALE_VALUES[value]
		scale_changed.emit(scale_factor)

## Aktualny współczynnik (tylko do odczytu z zewnątrz)
var scale_factor : float = 1.0

## Emitowany przy każdej zmianie trybu
signal scale_changed(new_scale: float)


func _ready() -> void:
	_load_saved()


## Ustawia tryb i zapisuje wybór gracza.
func set_mode(mode: ScaleMode) -> void:
	current_mode = mode
	_save()


## Zwraca listę etykiet wszystkich trybów (do OptionButton w opcjach).
func get_mode_labels() -> Array[String]:
	return [
		SCALE_LABELS[ScaleMode.SMALL],
		SCALE_LABELS[ScaleMode.NORMAL],
		SCALE_LABELS[ScaleMode.LARGE],
		SCALE_LABELS[ScaleMode.XLARGE],
	]


## Przelicza wartość pikselową z bazy 1080p na aktualny tryb skalowania.
func px(base_pixels: float) -> int:
	return roundi(base_pixels * scale_factor)


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
		var saved : int = cfg.get_value("ui", SAVE_KEY, ScaleMode.NORMAL)
		current_mode = saved as ScaleMode
	else:
		current_mode = ScaleMode.NORMAL
