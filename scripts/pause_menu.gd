extends CanvasLayer

@onready var _btn_resume  : Button = $Panel/VBox/BtnResume
@onready var _btn_menu    : Button = $Panel/VBox/BtnMenu
@onready var _btn_options : Button = $Panel/VBox/BtnOptions
@onready var _panel       : PanelContainer = $Panel

@onready var _options_menu : CanvasLayer = $OptionsMenu


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_btn_resume.pressed.connect(_on_resume)
	_btn_menu.pressed.connect(_on_menu)
	_btn_options.pressed.connect(_on_options)
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _on_scale_changed(_s: float) -> void:
	var fs := UIScaleManager.px(26)
	for btn in [_btn_resume, _btn_menu, _btn_options]:
		btn.add_theme_font_size_override("font_size", fs)
	_panel.custom_minimum_size = Vector2(UIScaleManager.px(300), UIScaleManager.px(220))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _options_menu.visible:
			return
		if visible:
			_on_resume()
		else:
			_show_pause()
		get_viewport().set_input_as_handled()


func _show_pause() -> void:
	get_tree().paused = true
	visible = true


func _on_resume() -> void:
	get_tree().paused = false
	visible = false


func _on_menu() -> void:
	get_tree().paused = false
	GameManager.return_to_menu()


func _on_options() -> void:
	_options_menu.open()
