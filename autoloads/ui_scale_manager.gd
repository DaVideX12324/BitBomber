extends Node
## Autoload: UIScaleManager
##
## Skaluje całe warstwy UI przez CanvasLayer.scale.
## Dzięki temu skalowane są WSZYSTKIE elementy (czcionki, przyciski,
## panele, marginesy, ikony) — bez żadnych ręcznych override’ów.
##
## Tryby:
##   SMALL  — 0.75×  (< 1280px)
##   NORMAL — 1.0×   (1280–1919px, baza FHD)
##   LARGE  — 1.5×   (1920–2559px)
##   XLARGE — 2.0×   (≥ 2560px, 4K)
##
## Użycie w skrypcie UI (jedyna potrzebna linia w _ready):
##   UIScaleManager.apply_to_layer(self)

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
		_apply_to_all_layers()
		scale_changed.emit(scale_factor)

var scale_factor : float = 1.0

signal scale_changed(new_scale: float)

# Wszystkie zarejestrowane warstwy UI
var _layers : Array[CanvasLayer] = []


func _ready() -> void:
	_load_saved()


## Rejestruje CanvasLayer i natychmiast aplikuje aktualne skalowanie.
## Wywołaj w _ready() każdego skryptu UI: UIScaleManager.apply_to_layer(self)
func apply_to_layer(layer: CanvasLayer) -> void:
	if not _layers.has(layer):
		_layers.append(layer)
		# Sprzątanie po usunięciu węzła
		layer.tree_exited.connect(func(): _layers.erase(layer))
	_set_layer_scale(layer)


## Ustawia tryb ręcznie i zapisuje wybór gracza.
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


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _apply_to_all_layers() -> void:
	for layer in _layers:
		if is_instance_valid(layer):
			_set_layer_scale(layer)


func _set_layer_scale(layer: CanvasLayer) -> void:
	layer.scale = Vector2(scale_factor, scale_factor)


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
	current_mode = _detect_mode()


func _detect_mode() -> ScaleMode:
	var w : int = DisplayServer.screen_get_size(
			DisplayServer.get_primary_screen()).x
	if   w >= 2560: return ScaleMode.XLARGE
	elif w >= 1920: return ScaleMode.LARGE
	elif w >= 1280: return ScaleMode.NORMAL
	else:           return ScaleMode.SMALL
