extends CanvasLayer

## Panel opcji wyświetlania.
## Otwierany z main menu przyciskiem "Opcje".
## Ustawienia są zapisywane przez SettingsManager.

@onready var _btn_windowed   : Button       = $Panel/VBox/HBoxMode/BtnWindowed
@onready var _btn_borderless : Button       = $Panel/VBox/HBoxMode/BtnBorderless
@onready var _btn_fullscreen : Button       = $Panel/VBox/HBoxMode/BtnFullscreen
@onready var _res_option     : OptionButton = $Panel/VBox/ResOption
@onready var _res_note       : Label        = $Panel/VBox/ResNote
@onready var _btn_apply      : Button       = $Panel/VBox/HBoxButtons/BtnApply
@onready var _btn_close      : Button       = $Panel/VBox/HBoxButtons/BtnClose

var _mode_btns  : Array[Button] = []
var _resolutions : Array[Vector2i] = []

# Mapowanie indeksu przycisku na stałą DisplayServer
const MODES : Array[int] = [
	DisplayServer.WINDOW_MODE_WINDOWED,
	DisplayServer.WINDOW_MODE_FULLSCREEN,   # borderless fullscreen
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_mode_btns = ([_btn_windowed, _btn_borderless, _btn_fullscreen] as Array[Button])
	_btn_apply.pressed.connect(_on_apply)
	_btn_close.pressed.connect(hide)
	for i in _mode_btns.size():
		var idx := i
		_mode_btns[i].pressed.connect(func(): _select_mode(idx))
	_populate_resolutions()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Otwieranie
# ---------------------------------------------------------------------------

func open() -> void:
	_sync_from_settings()
	visible = true


func _sync_from_settings() -> void:
	var cur_mode := SettingsManager.window_mode
	for i in MODES.size():
		_mode_btns[i].button_pressed = (MODES[i] == cur_mode)
	var cur_res := SettingsManager.resolution
	for i in _resolutions.size():
		if _resolutions[i] == cur_res:
			_res_option.selected = i
			break
	_update_res_note()


# ---------------------------------------------------------------------------
# Rozdzielczości
# ---------------------------------------------------------------------------

func _populate_resolutions() -> void:
	_resolutions = SettingsManager.get_available_resolutions()
	_res_option.clear()
	var screen_size := DisplayServer.screen_get_size()
	for r in _resolutions:
		var label := "%d × %d" % [r.x, r.y]
		if r == screen_size:
			label += "  (natywna)"
		_res_option.add_item(label)


# ---------------------------------------------------------------------------
# Tryb okna
# ---------------------------------------------------------------------------

func _select_mode(idx: int) -> void:
	for i in _mode_btns.size():
		_mode_btns[i].button_pressed = (i == idx)
	_update_res_note()


func _update_res_note() -> void:
	var selected_mode := _get_selected_mode()
	_res_option.disabled = (selected_mode != DisplayServer.WINDOW_MODE_WINDOWED)
	_res_note.visible    = (selected_mode != DisplayServer.WINDOW_MODE_WINDOWED)


func _get_selected_mode() -> int:
	for i in _mode_btns.size():
		if _mode_btns[i].button_pressed:
			return MODES[i]
	return DisplayServer.WINDOW_MODE_WINDOWED


# ---------------------------------------------------------------------------
# Zastosuj
# ---------------------------------------------------------------------------

func _on_apply() -> void:
	var mode := _get_selected_mode()
	SettingsManager.apply_window_mode(mode)
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var idx := _res_option.selected
		if idx >= 0 and idx < _resolutions.size():
			SettingsManager.apply_resolution(_resolutions[idx])
	hide()
