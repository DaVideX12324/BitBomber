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
@onready var _panel          : PanelContainer = $Panel

@onready var _confirm_popup  : PanelContainer = $ConfirmPopup
@onready var _lbl_countdown  : Label          = $ConfirmPopup/VBoxConfirm/LblCountdown
@onready var _btn_confirm    : Button         = $ConfirmPopup/VBoxConfirm/HBoxConfirm/BtnConfirm
@onready var _btn_revert     : Button         = $ConfirmPopup/VBoxConfirm/HBoxConfirm/BtnRevert

const CONFIRM_TIMEOUT := 20.0

var _mode_btns   : Array[Button]   = []
var _resolutions : Array[Vector2i] = []
var _sel_mode    : int             = 0

var _prev_mode    : int      = 0
var _prev_res     : Vector2i = Vector2i(1280, 720)
var _prev_monitor : int      = 0

var _countdown  : float = 0.0
var _confirming : bool  = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_mode_btns = ([_btn_windowed, _btn_borderless, _btn_fullscreen] as Array[Button])
	_btn_apply.pressed.connect(_on_apply)
	_btn_close.pressed.connect(_on_close)
	_btn_confirm.pressed.connect(_on_confirm)
	_btn_revert.pressed.connect(_on_revert)
	for i in _mode_btns.size():
		var idx := i
		_mode_btns[i].pressed.connect(func(): _select_mode(idx))
	_populate_monitors()
	_monitor_option.item_selected.connect(_on_monitor_changed)
	_populate_resolutions(_monitor_option.selected)
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _process(delta: float) -> void:
	if not _confirming:
		return
	_countdown -= delta
	if _countdown <= 0.0:
		_on_revert()
		return
	_lbl_countdown.text = "Przywrócenie za: %ds" % ceili(_countdown)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _confirming:
			_on_revert()
		else:
			_on_close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Skalowanie UI
# ---------------------------------------------------------------------------

func _on_scale_changed(_s: float) -> void:
	var fs_label  := UIScaleManager.px(20)
	var fs_button := UIScaleManager.px(18)
	for node in [$Panel/VBox/LblTitle] if has_node("Panel/VBox/LblTitle") else []:
		(node as Label).add_theme_font_size_override("font_size", UIScaleManager.px(26))
	for btn in _mode_btns:
		btn.add_theme_font_size_override("font_size", fs_button)
	_res_option.add_theme_font_size_override("font_size", fs_label)
	_monitor_option.add_theme_font_size_override("font_size", fs_label)
	_btn_apply.add_theme_font_size_override("font_size", fs_button)
	_btn_close.add_theme_font_size_override("font_size", fs_button)
	_btn_confirm.add_theme_font_size_override("font_size", fs_button)
	_btn_revert.add_theme_font_size_override("font_size", fs_button)
	_lbl_countdown.add_theme_font_size_override("font_size", fs_label)
	_panel.custom_minimum_size = Vector2(UIScaleManager.px(560), UIScaleManager.px(400))


# ---------------------------------------------------------------------------
# Otwieranie / zamykanie
# ---------------------------------------------------------------------------

func open() -> void:
	_sel_mode = SettingsManager.window_mode_idx
	_sync_mode_buttons()
	_monitor_option.selected = SettingsManager.monitor_idx
	_populate_resolutions(SettingsManager.monitor_idx)
	_sync_resolution()
	visible = true


func _on_close() -> void:
	if _confirming:
		_on_revert()
	else:
		hide()


# ---------------------------------------------------------------------------
# Synchronizacja UI
# ---------------------------------------------------------------------------

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


func _on_monitor_changed(idx: int) -> void:
	_populate_resolutions(idx)
	_res_option.selected = _resolutions.size() - 1


# ---------------------------------------------------------------------------
# Rozdzielczości
# ---------------------------------------------------------------------------

func _populate_resolutions(screen: int) -> void:
	var saved_idx := SettingsManager.monitor_idx
	SettingsManager.monitor_idx = screen
	_resolutions = SettingsManager.get_available_resolutions()
	SettingsManager.monitor_idx = saved_idx

	_res_option.clear()
	var screen_size := DisplayServer.screen_get_size(screen)
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
# Zastosuj + potwierdzenie
# ---------------------------------------------------------------------------

func _on_apply() -> void:
	_prev_mode    = SettingsManager.window_mode_idx
	_prev_res     = SettingsManager.resolution
	_prev_monitor = SettingsManager.monitor_idx

	var res_idx := _res_option.selected
	var res := SettingsManager.resolution
	if res_idx >= 0 and res_idx < _resolutions.size():
		res = _resolutions[res_idx]
	var screen := _monitor_option.selected
	SettingsManager.apply_settings(_sel_mode, res, screen)
	_start_confirm()


func _start_confirm() -> void:
	_countdown  = CONFIRM_TIMEOUT
	_confirming = true
	_confirm_popup.visible = true
	_lbl_countdown.text = "Przywrócenie za: %ds" % ceili(_countdown)


func _on_confirm() -> void:
	_confirming = false
	_confirm_popup.visible = false
	hide()


func _on_revert() -> void:
	_confirming = false
	_confirm_popup.visible = false
	SettingsManager.apply_settings(_prev_mode, _prev_res, _prev_monitor)
	_sel_mode = _prev_mode
	_sync_mode_buttons()
	_monitor_option.selected = _prev_monitor
	_populate_resolutions(_prev_monitor)
	_sync_resolution()
