extends Control

## Menu główne BitBomber.
## Oba panele (1P/2P) mają radio-style wybór liczby botów i trudności
## oraz osobny przycisk „Zagraj!“.

@onready var _btn1p   : Button         = $Center/Panel/VBox/Btn1P
@onready var _btn2p   : Button         = $Center/Panel/VBox/Btn2P
@onready var _panel1p : PanelContainer = $Center/Panel/VBox/Panel1P
@onready var _panel2p : PanelContainer = $Center/Panel/VBox/Panel2P

# Boty 1P
@onready var _bot1p : Array[Button] = [
	$"Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_1",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_2",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_3",
]
# Trudność 1P
@onready var _diff1p : Array[Button] = [
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Easy",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Medium",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Hard",
]
@onready var _start1p : Button = $Center/Panel/VBox/Panel1P/VBox1P/BtnStart1P

# Boty 2P
@onready var _bot2p : Array[Button] = [
	$"Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_1",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_2",
]
# Trudność 2P
@onready var _diff2p : Array[Button] = [
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Easy",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Medium",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Hard",
]
@onready var _start2p : Button = $Center/Panel/VBox/Panel2P/VBox2P/BtnStart2P

var _sel_bot_1p  : int = 0   # indeks wybranego przycisku botów 1P (0=1bot,1=2boty,2=3boty)
var _sel_bot_2p  : int = 0
var _sel_diff_1p : int = 0   # 0=Easy 1=Medium 2=Hard
var _sel_diff_2p : int = 0


func _ready() -> void:
	_btn1p.pressed.connect(_toggle_panel.bind(_panel1p, _panel2p))
	_btn2p.pressed.connect(_toggle_panel.bind(_panel2p, _panel1p))

	# Radio: boty 1P
	for i in _bot1p.size():
		var idx := i
		_bot1p[i].pressed.connect(func(): _set_bots(idx, true))

	# Radio: trudność 1P
	for i in _diff1p.size():
		var idx := i
		_diff1p[i].pressed.connect(func(): _set_diff(idx, true))

	_start1p.pressed.connect(func(): _start(1, _sel_bot_1p + 1, _sel_diff_1p))

	# Radio: boty 2P
	for i in _bot2p.size():
		var idx := i
		_bot2p[i].pressed.connect(func(): _set_bots(idx, false))

	# Radio: trudność 2P
	for i in _diff2p.size():
		var idx := i
		_diff2p[i].pressed.connect(func(): _set_diff(idx, false))

	_start2p.pressed.connect(func(): _start(2, _sel_bot_2p + 1, _sel_diff_2p))

	$Center/Panel/VBox/BtnQuit.pressed.connect(get_tree().quit)

	_refresh_bots(true);  _refresh_bots(false)
	_refresh_diff(true);  _refresh_diff(false)


# ---------------------------------------------------------------------------

func _toggle_panel(show_panel: PanelContainer, hide_panel: PanelContainer) -> void:
	hide_panel.visible = false
	show_panel.visible = not show_panel.visible


func _set_bots(idx: int, is_1p: bool) -> void:
	if is_1p: _sel_bot_1p = idx
	else:      _sel_bot_2p = idx
	_refresh_bots(is_1p)


func _set_diff(idx: int, is_1p: bool) -> void:
	if is_1p: _sel_diff_1p = idx
	else:      _sel_diff_2p = idx
	_refresh_diff(is_1p)


func _refresh_bots(is_1p: bool) -> void:
	var sel  := _sel_bot_1p if is_1p else _sel_bot_2p
	var btns := _bot1p      if is_1p else _bot2p
	for i in btns.size():
		btns[i].button_pressed = (i == sel)


func _refresh_diff(is_1p: bool) -> void:
	var sel  := _sel_diff_1p if is_1p else _sel_diff_2p
	var btns := _diff1p      if is_1p else _diff2p
	for i in btns.size():
		btns[i].button_pressed = (i == sel)


func _start(humans: int, bots: int, diff: int) -> void:
	GameManager.bot_difficulty = diff
	GameManager.start_game(humans, bots)
