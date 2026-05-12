extends CanvasLayer

@onready var _btn_start   : Button = $Center/VBox/BtnStart
@onready var _btn_options : Button = $Center/VBox/BtnOptions
@onready var _btn_quit    : Button = $Center/VBox/BtnQuit
@onready var _center      : Control = $Center

@onready var _options_menu : CanvasLayer = $OptionsMenu


func _ready() -> void:
	_btn_start.pressed.connect(_on_start)
	_btn_options.pressed.connect(_on_options)
	_btn_quit.pressed.connect(_on_quit)
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _on_scale_changed(s: float) -> void:
	var font_size := UIScaleManager.px(32)
	for btn in [_btn_start, _btn_options, _btn_quit]:
		btn.add_theme_font_size_override("font_size", font_size)
	_center.custom_minimum_size = Vector2(
		UIScaleManager.px(400),
		UIScaleManager.px(300)
	)


func _on_start() -> void:
	GameManager.start_game()


func _on_options() -> void:
	_options_menu.open()


func _on_quit() -> void:
	get_tree().quit()
