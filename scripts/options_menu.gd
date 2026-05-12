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
@onready var _scale_option   : OptionButton = $Panel/VBox/ScaleOption

@onready var _panel          : PanelContainer = $Panel
@onready var _title_label    : Label          = $Panel/VBox/Title
@onready var _mode_label     : Label          = $Panel/VBox/ModeLabel
@onready var _monitor_label  : Label          = $Panel/VBox/MonitorLabel
@onready var _res_label      : Label          = $Panel/VBox/ResLabel
@onready var _scale_label    : Label          = $Panel/VBox/ScaleLabel

@onready var _confirm_popup  : PanelContainer = $ConfirmPopup
@onready var _lbl_countdown  : Label          = $ConfirmPopup/VBoxConfirm/LblCountdown
@onready var _lbl_question   : Label          = $ConfirmPopup/VBoxConfirm/LblQuestion
@onready var _btn_confirm    : Button         = $ConfirmPopup/VBoxConfirm/HBoxConfirm/BtnConfirm
@onready var _btn_revert     : Button         = $ConfirmPopup/VBoxConfirm/HBoxConfirm/BtnRevert

const CONFIRM_TIMEOUT := 20.0

# Bazowe wymiary z .tscn (NORMAL = 1×)
const BASE_PANEL_HALF_W    := 280.0
const BASE_PANEL_HALF_H    := 340.0
const BASE_CONFIRM_HALF_W  := 220.0
const BASE_CONFIRM_HALF_H  := 100.0
const BASE_BTN_MODE_SIZE   := Vector2(80.0,  36.0)
const BASE_BTN_ACTION_SIZE := Vector2(130.0, 40.0)
const BASE_BTN_CONFIRM_SIZE := Vector2(140.0, 40.0)

var _mode_btns   : Array[Button]   = []
var _resolutions : Array[Vector2i] = []

# Aktualnie zaznaczony w UI (jeszcze nie zastosowany)
var _sel_mode    : int                      = 0
var _sel_scale   : UIScaleManager.ScaleMode = UIScaleManager.ScaleMode.NORMAL

# Snapshot stanu sprzed kliknięcia Zastosuj — używany przez Anuluj
var _prev_mode    : int                      = 0
var _prev_res     : Vector2i                 = Vector2i(1280, 720)
var _prev_monitor : int                      = 0
var _prev_scale   : UIScaleManager.ScaleMode = UIScaleManager.ScaleMode.NORMAL

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
	_populate_scale()
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
# Skalowanie — czcionki + rozmiary elementów
# ---------------------------------------------------------------------------

func _on_scale_changed(_s: float) -> void:
	_title_label.add_theme_font_size_override("font_size",    UIScaleManager.px(26))
	_mode_label.add_theme_font_size_override("font_size",     UIScaleManager.px(16))
	_monitor_label.add_theme_font_size_override("font_size",  UIScaleManager.px(16))
	_res_label.add_theme_font_size_override("font_size",      UIScaleManager.px(16))
	_res_note.add_theme_font_size_override("font_size",       UIScaleManager.px(12))
	_scale_label.add_theme_font_size_override("font_size",    UIScaleManager.px(16))
	_monitor_option.add_theme_font_size_override("font_size", UIScaleManager.px(16))
	_res_option.add_theme_font_size_override("font_size",     UIScaleManager.px(16))
	_scale_option.add_theme_font_size_override("font_size",   UIScaleManager.px(16))
	_btn_apply.add_theme_font_size_override("font_size",      UIScaleManager.px(17))
	_btn_close.add_theme_font_size_override("font_size",      UIScaleManager.px(17))
	_lbl_question.add_theme_font_size_override("font_size",   UIScaleManager.px(17))
	_lbl_countdown.add_theme_font_size_override("font_size",  UIScaleManager.px(22))
	_btn_confirm.add_theme_font_size_override("font_size",    UIScaleManager.px(16))
	_btn_revert.add_theme_font_size_override("font_size",     UIScaleManager.px(16))
	var fs_mode := UIScaleManager.px(15)
	for btn in _mode_btns:
		(btn as Button).add_theme_font_size_override("font_size", fs_mode)
	for btn in _mode_btns:
		(btn as Button).custom_minimum_size = UIScaleManager.sz2(
				BASE_BTN_MODE_SIZE.x, BASE_BTN_MODE_SIZE.y)
	_btn_apply.custom_minimum_size  = UIScaleManager.sz2(
			BASE_BTN_ACTION_SIZE.x, BASE_BTN_ACTION_SIZE.y)
	_btn_close.custom_minimum_size  = UIScaleManager.sz2(
			BASE_BTN_ACTION_SIZE.x, BASE_BTN_ACTION_SIZE.y)
	_btn_confirm.custom_minimum_size = UIScaleManager.sz2(
			BASE_BTN_CONFIRM_SIZE.x, BASE_BTN_CONFIRM_SIZE.y)
	_btn_revert.custom_minimum_size  = UIScaleManager.sz2(
			BASE_BTN_CONFIRM_SIZE.x, BASE_BTN_CONFIRM_SIZE.y)
	var ph := UIScaleManager.sz(BASE_PANEL_HALF_W)
	var pv := UIScaleManager.sz(BASE_PANEL_HALF_H)
	_panel.offset_left   = -ph
	_panel.offset_top    = -pv
	_panel.offset_right  =  ph
	_panel.offset_bottom =  pv
	var ch := UIScaleManager.sz(BASE_CONFIRM_HALF_W)
	var cv := UIScaleManager.sz(BASE_CONFIRM_HALF_H)
	_confirm_popup.offset_left   = -ch
	_confirm_popup.offset_top    = -cv
	_confirm_popup.offset_right  =  ch
	_confirm_popup.offset_bottom =  cv


# ---------------------------------------------------------------------------
# Otwieranie / zamykanie
# ---------------------------------------------------------------------------

## Zapisuje aktualny stan jako snapshot i otwiera panel.
func open() -> void:
	# Snapshot — będzie używany przez Anuluj
	_prev_mode    = SettingsManager.window_mode_idx
	_prev_res     = SettingsManager.resolution
	_prev_monitor = SettingsManager.monitor_idx
	_prev_scale   = UIScaleManager.current_mode
	# Wypełnij UI aktualnym stanem
	_sel_mode  = _prev_mode
	_sel_scale = _prev_scale
	_sync_mode_buttons()
	_monitor_option.selected = _prev_monitor
	_populate_resolutions(_prev_monitor)
	_sync_resolution()
	_sync_scale()
	visible = true


func _on_close() -> void:
	if _confirming:
		_on_revert()
	else:
		# Zamknięcie bez Zastosuj — przywróć skalę jeśli została zmieniona w UI
		if UIScaleManager.current_mode != _prev_scale:
			UIScaleManager.set_mode(_prev_scale)
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


func _sync_scale() -> void:
	_scale_option.selected = UIScaleManager.current_mode as int


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
# Skalowanie UI — tylko zaznaczenie w dropdownie, NIE aplikuj od razu
# ---------------------------------------------------------------------------

func _populate_scale() -> void:
	_scale_option.clear()
	for label in UIScaleManager.get_mode_labels():
		_scale_option.add_item(label)
	_sync_scale()
	_scale_option.item_selected.connect(_on_scale_item_selected)


## Zmiana w dropdownie — tylko zapamiętaj wybór, nie aplikuj jeszcze.
func _on_scale_item_selected(idx: int) -> void:
	_sel_scale = idx as UIScaleManager.ScaleMode


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
	var res_idx := _res_option.selected
	var res     := SettingsManager.resolution
	if res_idx >= 0 and res_idx < _resolutions.size():
		res = _resolutions[res_idx]
	var screen := _monitor_option.selected
	SettingsManager.apply_settings(_sel_mode, res, screen)
	UIScaleManager.set_mode(_sel_scale)
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
	UIScaleManager.set_mode(_prev_scale)
	_sel_mode  = _prev_mode
	_sel_scale = _prev_scale
	_sync_mode_buttons()
	_monitor_option.selected = _prev_monitor
	_populate_resolutions(_prev_monitor)
	_sync_resolution()
	_sync_scale()
