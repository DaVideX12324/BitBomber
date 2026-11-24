extends CanvasLayer

## Opcje gry samodzielnej (w hoście zastępuje je panel opcji hosta): Ekran / Dźwięk / Sterowanie.
## Ekran wymaga „Zastosuj” i potwierdzenia, dźwięk i klawisze działają od razu i zapisują się same.

signal closed

const P := "Center/Panel/VBox/"
const SCREEN := P + "Pages/Screen/"
const SOUND := P + "Pages/Sound/Grid/"
const CONTROLS := P + "Pages/Controls/"

const CONFIRM_TIMEOUT := 20.0
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const PLAYER_COLORS: Array[Color] = [Color("#3b82f6"), Color("#ef4444")]

## Wiersze zakładki Sterowanie: [podpis, akcja gracza 1, akcja gracza 2 ("" = brak)].
const BIND_ROWS: Array = [
	["Góra", "p1_up", "p2_up"],
	["Dół", "p1_down", "p2_down"],
	["Lewo", "p1_left", "p2_left"],
	["Prawo", "p1_right", "p2_right"],
	["Bomba", "p1_bomb", "p2_bomb"],
	["Odpowiedź 1", "quiz_p1_a", "quiz_p2_a"],
	["Odpowiedź 2", "quiz_p1_b", "quiz_p2_b"],
	["Odpowiedź 3", "quiz_p1_c", "quiz_p2_c"],
	["Odpowiedź 4", "quiz_p1_d", "quiz_p2_d"],
	["Pauza", "pause", ""],
]

@onready var _tab_btns: Array[Button] = [get_node(P + "TabRow/TabScreen"), get_node(P + "TabRow/TabSound"), get_node(P + "TabRow/TabControls")]
@onready var _pages: Array[Control] = [get_node(P + "Pages/Screen"), get_node(P + "Pages/Sound"), get_node(P + "Pages/Controls")]

# --- Ekran ---
@onready var _mode_btns: Array[Button] = [get_node(SCREEN + "Grid/HBoxMode/BtnWindowed"), get_node(SCREEN + "Grid/HBoxMode/BtnBorderless"), get_node(SCREEN + "Grid/HBoxMode/BtnFullscreen")]
@onready var _monitor_option: OptionButton = get_node(SCREEN + "Grid/MonitorOption")
@onready var _res_option: OptionButton = get_node(SCREEN + "Grid/ResOption")
@onready var _scale_option: OptionButton = get_node(SCREEN + "Grid/ScaleOption")
@onready var _btn_apply: Button = get_node(SCREEN + "BtnApply")

# --- Dźwięk ---
@onready var _sliders: Dictionary = {
	BUS_MASTER: get_node(SOUND + "SliderMaster"), BUS_MUSIC: get_node(SOUND + "SliderMusic"), BUS_SFX: get_node(SOUND + "SliderSfx"),
}
@onready var _pct_labels: Dictionary = {
	BUS_MASTER: get_node(SOUND + "PctMaster"), BUS_MUSIC: get_node(SOUND + "PctMusic"), BUS_SFX: get_node(SOUND + "PctSfx"),
}

# --- Sterowanie ---
@onready var _bind_grid: GridContainer = get_node(CONTROLS + "Scroll/BindGrid")
@onready var _btn_reset: Button = get_node(CONTROLS + "BtnReset")

@onready var _btn_close: Button = get_node(P + "BtnClose")
@onready var _confirm: Control = $Confirm
@onready var _lbl_countdown: Label = $Confirm/Center/Panel/VBox/LblCountdown
@onready var _btn_confirm: Button = $Confirm/Center/Panel/VBox/HBox/BtnConfirm
@onready var _btn_revert: Button = $Confirm/Center/Panel/VBox/HBox/BtnRevert

var _resolutions: Array[Vector2i] = []
var _sel_mode := 0
var _sel_scale := 2
var _scale_manually_changed := false

var _prev_mode := 0
var _prev_res := Vector2i(1280, 720)
var _prev_monitor := 0
var _prev_scale := 2
var _prev_scale_user_picked := false

var _countdown := 0.0
var _confirming := false
var _audio_changed := false

## Akcja czekająca na nowy klawisz ("" = nic) i jej przycisk.
var _capture_action := ""
var _capture_btn: Button = null
## Akcja -> przycisk z jej klawiszem.
var _bind_btns: Dictionary = {}

## Kontrolka -> [bazowy minimalny rozmiar, bazowy rozmiar czcionki] (skalowanie jak w menu głównym).
var _base_sizes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var tab_group := ButtonGroup.new()
	for i in _tab_btns.size():
		var idx := i
		_tab_btns[i].button_group = tab_group
		_tab_btns[i].pressed.connect(func(): _show_tab(idx))
	var mode_group := ButtonGroup.new()
	for i in _mode_btns.size():
		var idx := i
		_mode_btns[i].button_group = mode_group
		_mode_btns[i].pressed.connect(func(): _sel_mode = idx)
	_btn_apply.pressed.connect(_on_apply)
	_btn_close.pressed.connect(_on_close)
	_btn_confirm.pressed.connect(_on_confirm)
	_btn_revert.pressed.connect(_on_revert)
	_btn_reset.pressed.connect(_on_reset_binds)
	_populate_monitors()
	_monitor_option.item_selected.connect(_on_monitor_changed)
	_populate_resolutions(_monitor_option.selected)
	_populate_scale()
	for bus: String in _sliders:
		var slider: HSlider = _sliders[bus]
		var bus_name := bus
		slider.value_changed.connect(func(v: float): _on_volume_changed(bus_name, v))
	_build_bind_grid()
	_collect_base_sizes(self)
	var sm := _sm()
	if sm and sm.has_signal("scale_changed"):
		sm.scale_changed.connect(_on_scale_changed)
		_on_scale_changed(float(sm.get("scale_factor")))


func _process(delta: float) -> void:
	if not _confirming:
		return
	_countdown -= delta
	if _countdown <= 0.0:
		_on_revert()
		return
	_lbl_countdown.text = BbI18n.tf("bb.options.revert_countdown", {"time": ceili(_countdown)})


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capture_action != "":
		_capture_key(event)
		return
	if event.is_action_pressed("ui_cancel"):
		if _confirming:
			_on_revert()
		else:
			_on_close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Otwieranie / zamykanie / zakładki
# ---------------------------------------------------------------------------

func open() -> void:
	_prev_mode = _setting("window_mode_idx", 0)
	_prev_res = _setting("resolution", Vector2i(1280, 720))
	_prev_monitor = _setting("monitor_idx", 0)
	_prev_scale = int(_sm().get("current_mode")) if _sm() else 2
	_prev_scale_user_picked = _ui_scale_user_picked()
	_sel_mode = _prev_mode
	_sel_scale = _prev_scale
	_scale_manually_changed = false
	_sync_screen()
	_sync_audio_sliders()
	_refresh_bind_buttons()
	_show_tab(0)
	visible = true


func _on_close() -> void:
	if _confirming:
		_on_revert()
		return
	_cancel_capture()
	if _audio_changed:
		_audio_changed = false
		var settings := _settings_manager()
		if settings and settings.has_method("save_audio"):
			settings.save_audio()
	hide()
	closed.emit()


func _show_tab(idx: int) -> void:
	_cancel_capture()
	for i in _pages.size():
		_pages[i].visible = i == idx
		_tab_btns[i].set_pressed_no_signal(i == idx)


# ---------------------------------------------------------------------------
# Ekran
# ---------------------------------------------------------------------------

func _sm() -> Node:
	return get_node_or_null("/root/UIScaleManager")


func _settings_manager() -> Node:
	return get_node_or_null("/root/SettingsManager")


func _setting(property: String, default_value: Variant) -> Variant:
	var settings := _settings_manager()
	var value: Variant = settings.get(property) if settings else null
	return value if typeof(value) == typeof(default_value) else default_value


func _ui_scale_user_picked() -> bool:
	var sm := _sm()
	if sm == null:
		return false
	var current: Variant = sm.get("user_picked")
	if current != null:
		return bool(current)
	return bool(sm.get("_user_picked"))


func _sync_screen() -> void:
	for i in _mode_btns.size():
		_mode_btns[i].set_pressed_no_signal(i == _sel_mode)
	_monitor_option.selected = _prev_monitor
	_populate_resolutions(_prev_monitor)
	_res_option.selected = maxi(_resolutions.find(_prev_res), 0)
	_scale_option.selected = _prev_scale


func _populate_monitors() -> void:
	_monitor_option.clear()
	for i in DisplayServer.get_screen_count():
		var size := DisplayServer.screen_get_size(i)
		var label := "Monitor %d  (%d×%d)" % [i + 1, size.x, size.y]
		if i == DisplayServer.get_primary_screen():
			label += BbI18n.t("bb.options.primary_monitor_suffix", "  [główny]")
		_monitor_option.add_item(label)


func _on_monitor_changed(idx: int) -> void:
	_populate_resolutions(idx)
	_res_option.selected = _resolutions.size() - 1


## Rozdzielczości monitora wg SettingsManagera (liczy je dla swojego monitor_idx, więc podmieniamy go na chwilę).
func _populate_resolutions(screen: int) -> void:
	_resolutions.clear()
	var settings := _settings_manager()
	if settings and settings.has_method("get_available_resolutions"):
		var previous_monitor: Variant = settings.get("monitor_idx")
		settings.set("monitor_idx", screen)
		_resolutions.assign(settings.call("get_available_resolutions"))
		settings.set("monitor_idx", previous_monitor)
	_res_option.clear()
	var screen_size := DisplayServer.screen_get_size(screen)
	for r in _resolutions:
		var label := "%d × %d" % [r.x, r.y]
		if r == screen_size:
			label += BbI18n.t("bb.options.native_resolution_suffix", "  (natywna)")
		_res_option.add_item(label)


func _populate_scale() -> void:
	_scale_option.clear()
	var sm := _sm()
	var labels: Array = sm.call("get_mode_labels") if sm and sm.has_method("get_mode_labels") else []
	for label in labels:
		_scale_option.add_item(str(label))
	_scale_option.item_selected.connect(func(idx: int):
		_sel_scale = idx
		_scale_manually_changed = true)


func _on_apply() -> void:
	var res: Vector2i = _prev_res
	if _res_option.selected >= 0 and _res_option.selected < _resolutions.size():
		res = _resolutions[_res_option.selected]
	# Najpierw skala — apply_settings zapisze potem wszystko razem.
	var sm := _sm()
	if _scale_manually_changed and sm and sm.has_method("set_mode"):
		sm.set_mode(_sel_scale)
	elif not _prev_scale_user_picked and sm and sm.has_method("reset_to_auto"):
		sm.reset_to_auto()
	var settings := _settings_manager()
	if settings and settings.has_method("apply_settings"):
		settings.apply_settings(_sel_mode, res, _monitor_option.selected)
	_countdown = CONFIRM_TIMEOUT
	_confirming = true
	_confirm.visible = true
	_lbl_countdown.text = BbI18n.tf("bb.options.revert_countdown", {"time": ceili(_countdown)})


func _on_confirm() -> void:
	_confirming = false
	_confirm.visible = false
	_prev_mode = _sel_mode
	_prev_res = _setting("resolution", _prev_res)
	_prev_monitor = _monitor_option.selected
	_prev_scale = _scale_option.selected
	_prev_scale_user_picked = _ui_scale_user_picked()
	_scale_manually_changed = false


func _on_revert() -> void:
	_confirming = false
	_confirm.visible = false
	_scale_manually_changed = false
	var sm := _sm()
	if _prev_scale_user_picked and sm and sm.has_method("set_mode"):
		sm.set_mode(_prev_scale)
	elif sm and sm.has_method("reset_to_auto"):
		sm.reset_to_auto()
	var settings := _settings_manager()
	if settings and settings.has_method("apply_settings"):
		settings.apply_settings(_prev_mode, _prev_res, _prev_monitor)
	_sel_mode = _prev_mode
	_sel_scale = _prev_scale
	_sync_screen()


# ---------------------------------------------------------------------------
# Dźwięk
# ---------------------------------------------------------------------------

func _sync_audio_sliders() -> void:
	for bus: String in _sliders:
		var slider: HSlider = _sliders[bus]
		slider.set_value_no_signal(_bus_volume(bus))
		_update_pct(bus)
	_audio_changed = false


func _bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func _on_volume_changed(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	_update_pct(bus_name)
	_audio_changed = true


func _update_pct(bus_name: String) -> void:
	var slider: HSlider = _sliders[bus_name]
	var label: Label = _pct_labels[bus_name]
	label.text = "%d%%" % roundi(slider.value * 100.0)


# ---------------------------------------------------------------------------
# Sterowanie
# ---------------------------------------------------------------------------

func _build_bind_grid() -> void:
	_bind_grid.add_child(Control.new())
	for i in 2:
		var header := Label.new()
		header.text = "Gracz %d" % (i + 1)
		header.theme_type_variation = &"HeaderLabel"
		header.add_theme_color_override("font_color", PLAYER_COLORS[i])
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bind_grid.add_child(header)
	for row: Array in BIND_ROWS:
		var name_label := Label.new()
		name_label.text = row[0]
		name_label.theme_type_variation = &"HeaderLabel"
		name_label.custom_minimum_size = Vector2(170, 0)
		_bind_grid.add_child(name_label)
		for col in [1, 2]:
			var action: String = row[col]
			if action == "":
				_bind_grid.add_child(Control.new())
				continue
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 34)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 18)
			btn.pressed.connect(func(): _start_capture(action, btn))
			_bind_grid.add_child(btn)
			_bind_btns[action] = btn
	_refresh_bind_buttons()


func _refresh_bind_buttons() -> void:
	for action: String in _bind_btns:
		var btn: Button = _bind_btns[action]
		btn.text = BbInput.key_label(action, " / ")


func _start_capture(action: String, btn: Button) -> void:
	_cancel_capture()
	_capture_action = action
	_capture_btn = btn
	btn.text = BbI18n.t("bb.options.press_key", "Naciśnij klawisz…")


func _cancel_capture() -> void:
	_capture_action = ""
	_capture_btn = null
	_refresh_bind_buttons()


## Pierwszy wciśnięty klawisz trafia do czekającej akcji; Esc anuluje, kliknięcie myszą też.
func _capture_key(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_cancel_capture()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE:
		_cancel_capture()
		return
	var physical := key_event.physical_keycode
	if physical == KEY_NONE:
		physical = key_event.keycode
	BbInput.rebind(_capture_action, physical)
	BbInput.save()
	_cancel_capture()


func _on_reset_binds() -> void:
	BbInput.reset_defaults()
	BbInput.save()
	_cancel_capture()


# ---------------------------------------------------------------------------
# Skalowanie (jak menu główne: bazowe rozmiary × skala interfejsu)
# ---------------------------------------------------------------------------

func _on_scale_changed(_s: float) -> void:
	var sm := _sm()
	for c: Control in _base_sizes:
		if not is_instance_valid(c):
			continue
		var base: Array = _base_sizes[c]
		c.custom_minimum_size = sm.call("sz2", base[0].x, base[0].y) if sm else base[0]
		c.add_theme_font_size_override("font_size", int(sm.call("px", base[1])) if sm else base[1])
	for opt in [_monitor_option, _res_option, _scale_option]:
		(opt as OptionButton).get_popup().add_theme_font_size_override("font_size", int(sm.call("px", 19)) if sm else 19)


func _collect_base_sizes(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			_base_sizes[c] = [c.custom_minimum_size, c.get_theme_font_size("font_size")]
		if not c is OptionButton:
			_collect_base_sizes(c)
