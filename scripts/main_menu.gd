extends Control

## Menu główne BitBomber.
## 1P: radio 1-3 boty + trudność + Zagraj!
## 2P: radio 0-2 boty + trudność + Zagraj!
## Trudność ukryta gdy wybrano 0 botów w 2P.

@onready var _btn1p   : Button         = $Center/Panel/VBox/Btn1P
@onready var _btn2p   : Button         = $Center/Panel/VBox/Btn2P
@onready var _panel1p : PanelContainer = $Center/Panel/VBox/Panel1P
@onready var _panel2p : PanelContainer = $Center/Panel/VBox/Panel2P

# 1P
@onready var _bot1p : Array[Button] = [
	$"Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_1",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_2",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBox1P/Bot1P_3",
]
@onready var _diff1p : Array[Button] = [
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Easy",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Medium",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxDiff1P/Diff1P_Hard",
]
@onready var _start1p : Button = $Center/Panel/VBox/Panel1P/VBox1P/BtnStart1P

# 2P
@onready var _bot2p : Array[Button] = [
	$"Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_0",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_1",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBox2P/Bot2P_2",
]
@onready var _diff2p : Array[Button] = [
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Easy",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Medium",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P/Diff2P_Hard",
]
@onready var _diff_label2p : Label      = $Center/Panel/VBox/Panel2P/VBox2P/DiffLabel2P
@onready var _diff_hbox2p  : HBoxContainer = $Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P
@onready var _start2p      : Button     = $Center/Panel/VBox/Panel2P/VBox2P/BtnStart2P

# _bot2p[i] odpowiada liczbie botów = i (0, 1, 2)
var _sel_bot_1p  : int = 0   # 0=1bot 1=2boty 2=3boty
var _sel_bot_2p  : int = 0   # 0=0botów 1=1bot 2=2boty
var _sel_diff_1p : int = 0
var _sel_diff_2p : int = 0


func _ready() -> void:
	_btn1p.pressed.connect(_toggle_panel.bind(_panel1p, _panel2p))
	_btn2p.pressed.connect(_toggle_panel.bind(_panel2p, _panel1p))

	for i in _bot1p.size():
		var idx := i
		_bot1p[i].pressed.connect(func(): _set_bots(idx, true))

	for i in _diff1p.size():
		var idx := i
		_diff1p[i].pressed.connect(func(): _set_diff(idx, true))

	_start1p.pressed.connect(func(): _start(1, _sel_bot_1p + 1, _sel_diff_1p))

	for i in _bot2p.size():
		var idx := i
		_bot2p[i].pressed.connect(func(): _set_bots(idx, false))

	for i in _diff2p.size():
		var idx := i
		_diff2p[i].pressed.connect(func(): _set_diff(idx, false))

	# 2P: liczba botów to _sel_bot_2p (0, 1 lub 2 wprost)
	_start2p.pressed.connect(func(): _start(2, _sel_bot_2p, _sel_diff_2p))

	$Center/Panel/VBox/BtnQuit.pressed.connect(get_tree().quit)

	_refresh_bots(true);  _refresh_bots(false)
	_refresh_diff(true);  _refresh_diff(false)
	_update_diff_visibility()


# ---------------------------------------------------------------------------

func _toggle_panel(show_panel: PanelContainer, hide_panel: PanelContainer) -> void:
	hide_panel.visible = false
	show_panel.visible = not show_panel.visible


func _set_bots(idx: int, is_1p: bool) -> void:
	if is_1p: _sel_bot_1p = idx
	else:      _sel_bot_2p = idx
	_refresh_bots(is_1p)
	if not is_1p:
		_update_diff_visibility()


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


## Ukryj sekcję trudności w 2P gdy wybrano 0 botów
func _update_diff_visibility() -> void:
	var show := _sel_bot_2p > 0
	_diff_label2p.visible = show
	_diff_hbox2p.visible  = show


func _start(humans: int, bots: int, diff: int) -> void:
	GameManager.bot_difficulty = diff
	GameManager.start_game(humans, bots)
