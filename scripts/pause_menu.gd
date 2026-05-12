extends CanvasLayer

## Menu pauzy — wyświetlane po naciśnięciu ESC podczas rozgrywki.

@onready var _overlay      : ColorRect      = $Overlay
@onready var _panel        : PanelContainer = $Panel
@onready var _vbox         : VBoxContainer  = $Panel/VBox
@onready var _icon         : Label          = $Panel/VBox/Icon
@onready var _title        : Label          = $Panel/VBox/Title
@onready var _btn_resume   : Button         = $Panel/VBox/BtnResume
@onready var _btn_options  : Button         = $Panel/VBox/BtnOptions
@onready var _btn_menu     : Button         = $Panel/VBox/BtnMenu
@onready var _options_menu                  = $OptionsMenu

# Bazowe rozmiary z .tscn
const BASE_PANEL_HALF_W := 220.0
const BASE_PANEL_HALF_H := 200.0
const BASE_SEP_VBOX     := 12
const BASE_FS_ICON      := 52
const BASE_FS_TITLE     := 32
const BASE_FS_BTN       := 20
const BASE_BTN_SIZE     := Vector2(200.0, 44.0)

var _paused : bool = false


func _ready() -> void:
	visible = false
	_btn_resume.pressed.connect(resume)
	_btn_options.pressed.connect(_on_options)
	_btn_menu.pressed.connect(_on_menu)
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _on_scale_changed(_s: float) -> void:
	var ph := UIScaleManager.sz(BASE_PANEL_HALF_W)
	var pv := UIScaleManager.sz(BASE_PANEL_HALF_H)
	_panel.offset_left   = -ph ; _panel.offset_top    = -pv
	_panel.offset_right  =  ph ; _panel.offset_bottom =  pv
	_vbox.add_theme_constant_override("separation", UIScaleManager.px(BASE_SEP_VBOX))
	_icon.add_theme_font_size_override("font_size",         UIScaleManager.px(BASE_FS_ICON))
	_title.add_theme_font_size_override("font_size",        UIScaleManager.px(BASE_FS_TITLE))
	var fs_btn  := UIScaleManager.px(BASE_FS_BTN)
	var btn_sz  := UIScaleManager.sz2(BASE_BTN_SIZE.x, BASE_BTN_SIZE.y)
	for btn in [_btn_resume, _btn_options, _btn_menu]:
		(btn as Button).add_theme_font_size_override("font_size", fs_btn)
		(btn as Button).custom_minimum_size = btn_sz


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"): return
	# Nie pauzuj jeśli gra nie jest w trybie PLAYING
	if GameManager.current_state != GameManager.GameState.PLAYING: return
	# Nie pauzuj jeśli death_screen jest widoczny
	if _death_screen_visible(): return
	# Jeśli opcje są otwarte — zamknij je, nie wznawiaj
	if _options_menu.visible:
		return
	toggle()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Pauza / wznowienie
# ---------------------------------------------------------------------------

func toggle() -> void:
	if _paused: resume()
	else:       pause()


func pause() -> void:
	if _paused: return
	_paused = true
	get_tree().paused = true
	_show()


func resume() -> void:
	if not _paused: return
	# Nie wznawiaj gry gdy opcje są otwarte
	if _options_menu.visible: return
	_paused = false
	get_tree().paused = false
	_hide()


# ---------------------------------------------------------------------------
# Przyciski
# ---------------------------------------------------------------------------

func _on_options() -> void:
	_options_menu.open()


func _on_menu() -> void:
	_paused = false
	get_tree().paused = false
	visible = false
	GameManager.go_to_menu()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _death_screen_visible() -> bool:
	var gn := GameManager.game_node
	if not is_instance_valid(gn): return false
	var ds := gn.get_node_or_null("DeathScreen")
	return ds != null and ds.visible


func _show() -> void:
	visible = true
	_overlay.modulate.a = 0.0
	_panel.modulate.a   = 0.0
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.2)


func _hide() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 0.0, 0.15)
	tw.parallel().tween_property(_panel, "modulate:a", 0.0, 0.15)
	await tw.finished
	visible = false
