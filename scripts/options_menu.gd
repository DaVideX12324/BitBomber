extends CanvasLayer

## Panel opcji — zakładki: Ekran / Dźwięk / Sterowanie

# --- Ekran ---
@onready var _btn_windowed   : Button       = $Panel/VBox/Tabs/Ekran/HBoxMode/BtnWindowed
@onready var _btn_borderless : Button       = $Panel/VBox/Tabs/Ekran/HBoxMode/BtnBorderless
@onready var _btn_fullscreen : Button       = $Panel/VBox/Tabs/Ekran/HBoxMode/BtnFullscreen
@onready var _res_option     : OptionButton = $Panel/VBox/Tabs/Ekran/ResOption
@onready var _res_note       : Label        = $Panel/VBox/Tabs/Ekran/ResNote
@onready var _monitor_option : OptionButton = $Panel/VBox/Tabs/Ekran/MonitorOption
@onready var _scale_option   : OptionButton = $Panel/VBox/Tabs/Ekran/ScaleOption
@onready var _mode_label     : Label        = $Panel/VBox/Tabs/Ekran/ModeLabel
@onready var _monitor_label  : Label        = $Panel/VBox/Tabs/Ekran/MonitorLabel
@onready var _res_label      : Label        = $Panel/VBox/Tabs/Ekran/ResLabel
@onready var _scale_label    : Label        = $Panel/VBox/Tabs/Ekran/ScaleLabel

# --- Dźwięk ---
@onready var _slider_master : HSlider = $Panel/VBox/Tabs/Dzwiek/SliderMaster
@onready var _slider_music  : HSlider = $Panel/VBox/Tabs/Dzwiek/SliderMusic
@onready var _slider_sfx    : HSlider = $Panel/VBox/Tabs/Dzwiek/SliderSfx
@onready var _lbl_master    : Label   = $Panel/VBox/Tabs/Dzwiek/LblMaster
@onready var _lbl_music     : Label   = $Panel/VBox/Tabs/Dzwiek/LblMusic
@onready var _lbl_sfx       : Label   = $Panel/VBox/Tabs/Dzwiek/LblSfx

# --- Sterowanie ---
@onready var _binds_list : VBoxContainer = $Panel/VBox/Tabs/Sterowanie/BindsList
@onready var _lbl_info   : Label         = $Panel/VBox/Tabs/Sterowanie/LblInfo

# --- Wspólne ---
@onready var _panel       : PanelContainer = $Panel
@onready var _title_label : Label          = $Panel/VBox/Title
@onready var _tabs        : TabContainer   = $Panel/VBox/Tabs
@onready var _btn_apply   : Button         = $Panel/VBox/HBoxButtons/BtnApply
@onready var _btn_close   : Button         = $Panel/VBox/HBoxButtons/BtnClose

@onready var _confirm_popup : PanelContainer = $ConfirmPopup
@onready var _lbl_countdown : Label          = $ConfirmPopup/VBoxConfirm/LblCountdown
@onready var _lbl_question  : Label          = $ConfirmPopup/VBoxConfirm/LblQuestion
@onready var _btn_confirm   : Button         = $ConfirmPopup/VBoxConfirm/HBoxConfirm/BtnConfirm
@onready var _btn_revert    : Button         = $ConfirmPopup/VBoxConfirm/HBoxConfirm/BtnRevert

const CONFIRM_TIMEOUT := 20.0

const BASE_PANEL_HALF_W     := 300.0
const BASE_PANEL_HALF_H     := 360.0
const BASE_CONFIRM_HALF_W   := 220.0
const BASE_CONFIRM_HALF_H   := 100.0
const BASE_BTN_MODE_SIZE    := Vector2(80.0,  36.0)
const BASE_BTN_ACTION_SIZE  := Vector2(130.0, 40.0)
const BASE_BTN_CONFIRM_SIZE := Vector2(140.0, 40.0)

var _mode_btns   : Array[Button]   = []
var _resolutions : Array[Vector2i] = []

var _sel_mode  : int                      = 0
var _sel_scale : UIScaleManager.ScaleMode = UIScaleManager.ScaleMode.NORMAL
var _scale_manually_changed : bool        = false

var _prev_mode              : int                      = 0
var _prev_res               : Vector2i                 = Vector2i(1280, 720)
var _prev_monitor           : int                      = 0
var _prev_scale             : UIScaleManager.ScaleMode = UIScaleManager.ScaleMode.NORMAL
var _prev_scale_user_picked : bool                     = false

var _countdown  : float = 0.0
var _confirming : bool  = false

const BUS_MASTER := "Master"
const BUS_MUSIC  := "Music"
const BUS_SFX    := "SFX"


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
	_setup_audio_sliders()
	_populate_binds()
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
	var main_size := UIScaleManager.px(18)
	# Tytuł
	_title_label.add_theme_font_size_override("font_size", UIScaleManager.px(26))
	# Zakładki TabContainer — napis na samych zakładkach
	_tabs.add_theme_font_size_override("font_size", UIScaleManager.px(17))
	# Ekran
	_mode_label.add_theme_font_size_override("font_size",    main_size)
	_monitor_label.add_theme_font_size_override("font_size", main_size)
	_res_label.add_theme_font_size_override("font_size",     main_size)
	_res_note.add_theme_font_size_override("font_size",      UIScaleManager.px(15))
	_scale_label.add_theme_font_size_override("font_size",   main_size)
	_monitor_option.add_theme_font_size_override("font_size", main_size)
	_res_option.add_theme_font_size_override("font_size",     main_size)
	_scale_option.add_theme_font_size_override("font_size",   main_size)
	# Dropdown (PopupMenu) każdego OptionButton
	_scale_popup_font(_monitor_option, main_size)
	_scale_popup_font(_res_option,     main_size)
	_scale_popup_font(_scale_option,   main_size)
	# Dźwięk
	_lbl_master.add_theme_font_size_override("font_size", main_size)
	_lbl_music.add_theme_font_size_override("font_size",  main_size)
	_lbl_sfx.add_theme_font_size_override("font_size",    main_size)
	# Sterowanie
	_lbl_info.add_theme_font_size_override("font_size", UIScaleManager.px(14))
	for child in _binds_list.get_children():
		if child is Label:
			(child as Label).add_theme_font_size_override("font_size", UIScaleManager.px(14))
	# Przyciski akcji
	_btn_apply.add_theme_font_size_override("font_size",    UIScaleManager.px(20))
	_btn_close.add_theme_font_size_override("font_size",    UIScaleManager.px(20))
	_lbl_question.add_theme_font_size_override("font_size", UIScaleManager.px(18))
	_lbl_countdown.add_theme_font_size_override("font_size",UIScaleManager.px(22))
	_btn_confirm.add_theme_font_size_override("font_size",  UIScaleManager.px(20))
	_btn_revert.add_theme_font_size_override("font_size",   UIScaleManager.px(20))
	var fs_mode := UIScaleManager.px(15)
	for btn in _mode_btns:
		(btn as Button).add_theme_font_size_override("font_size", fs_mode)
		(btn as Button).custom_minimum_size = UIScaleManager.sz2(BASE_BTN_MODE_SIZE.x, BASE_BTN_MODE_SIZE.y)
	_btn_apply.custom_minimum_size   = UIScaleManager.sz2(BASE_BTN_ACTION_SIZE.x,  BASE_BTN_ACTION_SIZE.y)
	_btn_close.custom_minimum_size   = UIScaleManager.sz2(BASE_BTN_ACTION_SIZE.x,  BASE_BTN_ACTION_SIZE.y)
	_btn_confirm.custom_minimum_size = UIScaleManager.sz2(BASE_BTN_CONFIRM_SIZE.x, BASE_BTN_CONFIRM_SIZE.y)
	_btn_revert.custom_minimum_size  = UIScaleManager.sz2(BASE_BTN_CONFIRM_SIZE.x, BASE_BTN_CONFIRM_SIZE.y)
	var ph := UIScaleManager.sz(BASE_PANEL_HALF_W)
	var pv := UIScaleManager.sz(BASE_PANEL_HALF_H)
	_panel.offset_left   = -ph ; _panel.offset_top    = -pv
	_panel.offset_right  =  ph ; _panel.offset_bottom =  pv
	var ch := UIScaleManager.sz(BASE_CONFIRM_HALF_W)
	var cv := UIScaleManager.sz(BASE_CONFIRM_HALF_H)
	_confirm_popup.offset_left   = -ch ; _confirm_popup.offset_top    = -cv
	_confirm_popup.offset_right  =  ch ; _confirm_popup.offset_bottom =  cv


## Ustawia rozmiar czcionki w rozwijanym PopupMenu OptionButtona.
func _scale_popup_font(opt: OptionButton, font_size: int) -> void:
	var popup := opt.get_popup()
	popup.add_theme_font_size_override("font_size", font_size)


# ---------------------------------------------------------------------------
# Otwieranie / zamykanie
# ---------------------------------------------------------------------------

func open() -> void:
	_prev_mode              = SettingsManager.window_mode_idx
	_prev_res               = SettingsManager.resolution
	_prev_monitor           = SettingsManager.monitor_idx
	_prev_scale             = UIScaleManager.current_mode
	_prev_scale_user_picked = UIScaleManager._user_picked
	_sel_mode               = _prev_mode
	_sel_scale              = _prev_scale
	_scale_manually_changed = false
	_sync_mode_buttons()
	_monitor_option.selected = _prev_monitor
	_populate_resolutions(_prev_monitor)
	_sync_resolution()
	_sync_scale()
	_sync_audio_sliders()
	visible = true


func _on_close() -> void:
	if _confirming:
		_on_revert()
	else:
		hide()


# ---------------------------------------------------------------------------
# Ekran
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


func _populate_monitors() -> void:
	_monitor_option.clear()
	for i in DisplayServer.get_screen_count():
		var size := DisplayServer.screen_get_size(i)
		var label := "Monitor %d  (%d×%d)" % [i + 1, size.x, size.y]
		if i == DisplayServer.get_primary_screen():
			label += "  [główny]"
		_monitor_option.add_item(label)


func _on_monitor_changed(idx: int) -> void:
	_populate_resolutions(idx)
	_res_option.selected = _resolutions.size() - 1


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


func _populate_scale() -> void:
	_scale_option.clear()
	for label in UIScaleManager.get_mode_labels():
		_scale_option.add_item(label)
	_sync_scale()
	_scale_option.item_selected.connect(_on_scale_item_selected)


func _on_scale_item_selected(idx: int) -> void:
	_sel_scale = idx as UIScaleManager.ScaleMode
	_scale_manually_changed = true


func _select_mode(idx: int) -> void:
	_sel_mode = idx
	_sync_mode_buttons()


func _update_res_note() -> void:
	_res_option.disabled = false
	_res_note.visible    = false


# ---------------------------------------------------------------------------
# Dźwięk
# ---------------------------------------------------------------------------

func _setup_audio_sliders() -> void:
	_slider_master.value_changed.connect(_on_master_changed)
	_slider_music.value_changed.connect(_on_music_changed)
	_slider_sfx.value_changed.connect(_on_sfx_changed)


func _sync_audio_sliders() -> void:
	_slider_master.value = _bus_volume(BUS_MASTER)
	_slider_music.value  = _bus_volume(BUS_MUSIC)
	_slider_sfx.value    = _bus_volume(BUS_SFX)


func _bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0: return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _on_master_changed(v: float) -> void: _set_bus_volume(BUS_MASTER, v)
func _on_music_changed(v: float)  -> void: _set_bus_volume(BUS_MUSIC,  v)
func _on_sfx_changed(v: float)    -> void: _set_bus_volume(BUS_SFX,    v)


# ---------------------------------------------------------------------------
# Sterowanie
# ---------------------------------------------------------------------------

const BINDS : Array = [
	["Gracz 1 — ruch",  ["p1_up", "p1_down", "p1_left", "p1_right"]],
	["Gracz 1 — bomba", ["p1_bomb"]],
	["Gracz 2 — ruch",  ["p2_up", "p2_down", "p2_left", "p2_right"]],
	["Gracz 2 — bomba", ["p2_bomb"]],
	["Pauza",            ["pause"]],
]


func _populate_binds() -> void:
	for child in _binds_list.get_children():
		child.queue_free()
	for entry in BINDS:
		var section : String = entry[0]
		var actions : Array  = entry[1]
		var lbl_sec := Label.new()
		lbl_sec.text = section
		lbl_sec.add_theme_font_size_override("font_size", UIScaleManager.px(14))
		lbl_sec.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
		_binds_list.add_child(lbl_sec)
		var keys : Array[String] = []
		for action in actions:
			if not InputMap.has_action(action): continue
			for event in InputMap.action_get_events(action):
				if event is InputEventKey:
					keys.append(event.as_text_physical_keycode())
					break
		var lbl_keys := Label.new()
		lbl_keys.text = "  " + ", ".join(keys) if keys.size() > 0 else "  (brak)"
		lbl_keys.add_theme_font_size_override("font_size", UIScaleManager.px(13))
		lbl_keys.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		_binds_list.add_child(lbl_keys)


# ---------------------------------------------------------------------------
# Zastosuj + potwierdzenie
# ---------------------------------------------------------------------------

func _on_apply() -> void:
	var res_idx := _res_option.selected
	var res     := SettingsManager.resolution
	if res_idx >= 0 and res_idx < _resolutions.size():
		res = _resolutions[res_idx]
	SettingsManager.apply_settings(_sel_mode, res, _monitor_option.selected)
	if _scale_manually_changed:
		UIScaleManager.set_mode(_sel_scale)
	else:
		if not _prev_scale_user_picked:
			UIScaleManager.reset_to_auto()
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
	_scale_manually_changed = false
	SettingsManager.apply_settings(_prev_mode, _prev_res, _prev_monitor)
	if _prev_scale_user_picked:
		UIScaleManager.set_mode(_prev_scale)
	else:
		UIScaleManager.reset_to_auto()
	_sel_mode  = _prev_mode
	_sel_scale = _prev_scale
	_sync_mode_buttons()
	_monitor_option.selected = _prev_monitor
	_populate_resolutions(_prev_monitor)
	_sync_resolution()
	_sync_scale()
	_sync_audio_sliders()
