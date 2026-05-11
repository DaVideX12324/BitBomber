extends CanvasLayer

## Panel opcji wyświetlania.

@onready var _btn_windowed   : Button       = $Panel/VBox/HBoxMode/BtnWindowed
@onready var _btn_borderless : Button       = $Panel/VBox/HBoxMode/BtnBorderless
@onready var _btn_fullscreen : Button       = $Panel/VBox/HBoxMode/BtnFullscreen
@onready var _res_option     : OptionButton = $Panel/VBox/ResOption
@onready var _res_note       : Label        = $Panel/VBox/ResNote
@onready var _monitor_option : OptionButton = $Panel/VBox/MonitorOption
@onready var _btn_apply      : Button       = $Panel/VBox/HBoxButtons/BtnApply
@onready var _btn_close      : Button       = $Panel/VBox/HBoxButtons/BtnClose

var _mode_btns   : Array[Button]   = []
var _resolutions : Array[Vector2i] = []
var _sel_mode    : int             = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_mode_btns = ([_btn_windowed, _btn_borderless, _btn_fullscreen] as Array[Button])
	_btn_apply.pressed.connect(_on_apply)
	_btn_close.pressed.connect(hide)
	for i in _mode_btns.size():
		var idx := i
		_mode_btns[i].pressed.connect(func(): _select_mode(idx))
	_populate_monitors()
	_populate_resolutions()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Otwieranie
# ---------------------------------------------------------------------------

func open() -> void:
	_sel_mode = SettingsManager.window_mode_idx
	_sync_mode_buttons()
	_sync_resolution()
	_monitor_option.selected = SettingsManager.monitor_idx
	visible = true


func _sync_mode_buttons() -> void:
	for i in _mode_btns.size():
		_mode_btns[i].button_pressed = (i == _sel_mode)
	_update_res_note()


func _sync_resolution() -> void:
	var cur_res := SettingsManager.resolution
	for i in _resolutions.size():
		if _resolutions[i] == cur_res:
			_res_option.selected = i
			return
	_res_option.selected = 0


# ---------------------------------------------------------------------------
# Monitory
# ---------------------------------------------------------------------------

func _populate_monitors() -> void:
	_monitor_option.clear()
	var count := DisplayServer.get_screen_count()
	for i in count:
		var size := DisplayServer.screen_get_size(i)
		var label := "Monitor %d  (%d×%d)" % [i + 1, size.x, size.y]
		if i == DisplayServer.get_primary_screen():
			label += "  [główny]"
		_monitor_option.add_item(label)


# ---------------------------------------------------------------------------
# Rozdzielczości
# ---------------------------------------------------------------------------

func _populate_resolutions() -> void:
	_resolutions = SettingsManager.get_available_resolutions()
	_res_option.clear()
	var screen_size := DisplayServer.screen_get_size(SettingsManager.monitor_idx)
	for r in _resolutions:
		var label := "%d × %d" % [r.x, r.y]
		if r == screen_size:
			label += "  (natywna)"
		_res_option.add_item(label)


# ---------------------------------------------------------------------------
# Tryb okna
# ---------------------------------------------------------------------------

func _select_mode(idx: int) -> void:
	_sel_mode = idx
	_sync_mode_buttons()


func _update_res_note() -> void:
	_res_option.disabled = false
	_res_note.visible    = false


# ---------------------------------------------------------------------------
# Zastosuj
# ---------------------------------------------------------------------------

func _on_apply() -> void:
	var res_idx := _res_option.selected
	var res := SettingsManager.resolution
	if res_idx >= 0 and res_idx < _resolutions.size():
		res = _resolutions[res_idx]
	var screen := _monitor_option.selected
	SettingsManager.apply_settings(_sel_mode, res, screen)
	hide()
