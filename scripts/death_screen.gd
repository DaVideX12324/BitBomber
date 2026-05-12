extends CanvasLayer

@onready var _lbl_title    : Label  = $Center/Panel/VBox/LblTitle
@onready var _lbl_subtitle : Label  = $Center/Panel/VBox/LblSubtitle
@onready var _btn_rematch  : Button = $Center/Panel/VBox/BtnRematch
@onready var _btn_menu     : Button = $Center/Panel/VBox/BtnMenu
@onready var _panel        : PanelContainer = $Center/Panel


func _ready() -> void:
	visible = false
	_btn_rematch.pressed.connect(_on_rematch)
	_btn_menu.pressed.connect(_on_menu)
	GameManager.game_over.connect(_on_game_over)
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _on_scale_changed(_s: float) -> void:
	_lbl_title.add_theme_font_size_override("font_size", UIScaleManager.px(48))
	_lbl_subtitle.add_theme_font_size_override("font_size", UIScaleManager.px(28))
	for btn in [_btn_rematch, _btn_menu]:
		btn.add_theme_font_size_override("font_size", UIScaleManager.px(26))
	_panel.custom_minimum_size = Vector2(UIScaleManager.px(480), UIScaleManager.px(300))


func _on_game_over(winner_name: String) -> void:
	_lbl_title.text    = "%s wygrywa!" % winner_name
	_lbl_subtitle.text = "Koniec gry"
	visible = true


func _on_rematch() -> void:
	GameManager.start_game()


func _on_menu() -> void:
	GameManager.return_to_menu()
