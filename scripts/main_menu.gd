extends Control

## Menu główne BitBomber.
## Kliknięcie Btn1P/Btn2P rozwija panel wyboru liczby botów.
## Kliknięcie przycisku bota natychmiast startuje grę.

@onready var _btn1p   : Button         = $Center/Panel/VBox/Btn1P
@onready var _btn2p   : Button         = $Center/Panel/VBox/Btn2P
@onready var _panel1p : PanelContainer = $Center/Panel/VBox/Panel1P
@onready var _panel2p : PanelContainer = $Center/Panel/VBox/Panel2P


func _ready() -> void:
	_btn1p.pressed.connect(_toggle_panel.bind(_panel1p, _panel2p))
	_btn2p.pressed.connect(_toggle_panel.bind(_panel2p, _panel1p))

	# 1P — 1/2/3 boty
	$Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_1.pressed.connect(func(): _start(1, 1))
	$Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_2.pressed.connect(func(): _start(1, 2))
	$Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_3.pressed.connect(func(): _start(1, 3))

	# 2P — 1/2 boty
	$Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_1.pressed.connect(func(): _start(2, 1))
	$Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_2.pressed.connect(func(): _start(2, 2))

	$Center/Panel/VBox/BtnQuit.pressed.connect(get_tree().quit)


func _toggle_panel(show_panel: PanelContainer, hide_panel: PanelContainer) -> void:
	hide_panel.visible = false
	show_panel.visible = not show_panel.visible


func _start(humans: int, bots: int) -> void:
	GameManager.start_game(humans, bots)
