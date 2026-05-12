extends Node
## Autoload: UIScaleManager
## Śledzi aktualny współczynnik skalowania UI względem rozdzielczości bazowej.
## Przy stretch/mode=disabled viewport ma dokładnie rozmiar okna — UI musi samo
## przeliczać rozmiary. Subskrybuj sygnał scale_changed lub czytaj scale_factor.

const BASE_RES := Vector2(1920.0, 1080.0)

## Aktualny współczynnik skalowania (1.0 = pełne 1080p)
var scale_factor : float = 1.0

## Emitowany przy każdej zmianie rozmiaru okna
signal scale_changed(new_scale: float)


func _ready() -> void:
	get_tree().root.size_changed.connect(_on_window_resized)
	_recalculate()


func _on_window_resized() -> void:
	_recalculate()


func _recalculate() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var sx  := win.x / BASE_RES.x
	var sy  := win.y / BASE_RES.y
	var new_scale := minf(sx, sy)
	if absf(new_scale - scale_factor) < 0.001:
		return
	scale_factor = new_scale
	scale_changed.emit(scale_factor)


## Przelicza wartość pikselową z bazy 1080p na aktualną rozdzielczość.
## Użyj do font_size, custom_minimum_size itp.
func px(base_pixels: float) -> int:
	return roundi(base_pixels * scale_factor)
