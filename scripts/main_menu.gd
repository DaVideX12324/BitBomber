extends Control

## Menu główne BitBomber.
## Kliknięcie Btn1P/Btn2P rozwija panel wyboru liczby botów.
## Pod wyborem botów widoczny jest rząd wyboru trudności (radio-style toggle).
## Kliknięcie przycisku liczby botów natychmiast startuje grę z wybraną trudnością.

@onready var _btn1p   : Button         = $Center/Panel/VBox/Btn1P
@onready var _btn2p   : Button         = $Center/Panel/VBox/Btn2P
@onready var _panel1p : PanelContainer = $Center/Panel/VBox/Panel1P
@onready var _panel2p : PanelContainer = $Center/Panel/VBox/Panel2P

# Przyciski trudności 1P
@onready var _diff1p_easy   : Button = $Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Easy
@onready var _diff1p_medium : Button = $Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Medium
@onready var _diff1p_hard   : Button = $Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Hard

# Przyciski trudności 2P
@onready var _diff2p_easy   : Button = $Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Easy
@onready var _diff2p_medium : Button = $Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Medium
@onready var _diff2p_hard   : Button = $Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Hard

# Aktualnie wybrana trudność (0=Easy 1=Medium 2=Hard)
var _selected_diff_1p : int = 0
var _selected_diff_2p : int = 0


func _ready() -> void:
	_btn1p.pressed.connect(_toggle_panel.bind(_panel1p, _panel2p))
	_btn2p.pressed.connect(_toggle_panel.bind(_panel2p, _panel1p))

	# 1P — liczba botów
	$Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_1.pressed.connect(func(): _start(1, 1, _selected_diff_1p))
	$Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_2.pressed.connect(func(): _start(1, 2, _selected_diff_1p))
	$Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_3.pressed.connect(func(): _start(1, 3, _selected_diff_1p))

	# 2P — liczba botów
	$Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_1.pressed.connect(func(): _start(2, 1, _selected_diff_2p))
	$Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_2.pressed.connect(func(): _start(2, 2, _selected_diff_2p))

	# 1P — trudność (radio)
	_diff1p_easy.pressed.connect(func():   _set_diff(0, true))
	_diff1p_medium.pressed.connect(func(): _set_diff(1, true))
	_diff1p_hard.pressed.connect(func():   _set_diff(2, true))

	# 2P — trudność (radio)
	_diff2p_easy.pressed.connect(func():   _set_diff(0, false))
	_diff2p_medium.pressed.connect(func(): _set_diff(1, false))
	_diff2p_hard.pressed.connect(func():   _set_diff(2, false))

	$Center/Panel/VBox/BtnQuit.pressed.connect(get_tree().quit)

	_refresh_diff_buttons(true)
	_refresh_diff_buttons(false)


# ---------------------------------------------------------------------------

func _toggle_panel(show_panel: PanelContainer, hide_panel: PanelContainer) -> void:
	hide_panel.visible = false
	show_panel.visible = not show_panel.visible


## Ustaw trudność i odśwież wizualny stan przycisków (radio-style).
func _set_diff(level: int, is_1p: bool) -> void:
	if is_1p:
		_selected_diff_1p = level
	else:
		_selected_diff_2p = level
	_refresh_diff_buttons(is_1p)


func _refresh_diff_buttons(is_1p: bool) -> void:
	var level := _selected_diff_1p if is_1p else _selected_diff_2p
	var btns : Array[Button]
	if is_1p:
		btns = [_diff1p_easy, _diff1p_medium, _diff1p_hard]
	else:
		btns = [_diff2p_easy, _diff2p_medium, _diff2p_hard]
	for i in btns.size():
		btns[i].button_pressed = (i == level)


func _start(humans: int, bots: int, diff: int) -> void:
	GameManager.bot_difficulty = diff
	GameManager.start_game(humans, bots)
