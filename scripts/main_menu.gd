extends CanvasLayer

## Menu główne BitBomber.
## 1P: radio 1-3 boty + trudność + tryb wygranej + Zagraj!
## 2P: radio 0-2 boty + trudność + tryb wygranej + Zagraj!
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
@onready var _win1p : Array[Button] = [
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxWin1P/Win1P_FirstTo",
	$"Center/Panel/VBox/Panel1P/VBox1P/HBoxWin1P/Win1P_MostWins",
]
@onready var _rounds_spin1p : SpinBox = $"Center/Panel/VBox/Panel1P/VBox1P/HBoxRounds1P/RoundsSpin1P"
@onready var _rounds_label1p : Label  = $"Center/Panel/VBox/Panel1P/VBox1P/HBoxRounds1P/RoundsLabel1P"
@onready var _quiz_opt1p : OptionButton = $Center/Panel/VBox/Panel1P/VBox1P/QuizOpt1P
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
@onready var _win2p : Array[Button] = [
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxWin2P/Win2P_FirstTo",
	$"Center/Panel/VBox/Panel2P/VBox2P/HBoxWin2P/Win2P_MostWins",
]
@onready var _rounds_spin2p  : SpinBox        = $"Center/Panel/VBox/Panel2P/VBox2P/HBoxRounds2P/RoundsSpin2P"
@onready var _rounds_label2p : Label          = $"Center/Panel/VBox/Panel2P/VBox2P/HBoxRounds2P/RoundsLabel2P"
@onready var _diff_label2p   : Label          = $Center/Panel/VBox/Panel2P/VBox2P/DiffLabel2P
@onready var _diff_hbox2p    : HBoxContainer  = $Center/Panel/VBox/Panel2P/VBox2P/HBoxDiff2P
@onready var _quiz_opt2p : OptionButton = $Center/Panel/VBox/Panel2P/VBox2P/QuizOpt2P
@onready var _start2p        : Button         = $Center/Panel/VBox/Panel2P/VBox2P/BtnStart2P

var _sel_bot_1p  : int = 0
var _sel_bot_2p  : int = 0
var _sel_diff_1p : int = 0
var _sel_diff_2p : int = 0
var _sel_win_1p  : int = 0   ## 0 = FIRST_TO_X, 1 = MOST_WINS_IN_Y
var _sel_win_2p  : int = 0


func _ready() -> void:
	_btn1p.pressed.connect(_toggle_panel.bind(_panel1p, _panel2p))
	_btn2p.pressed.connect(_toggle_panel.bind(_panel2p, _panel1p))

	for i in _bot1p.size():
		var idx := i
		_bot1p[i].pressed.connect(func(): _set_bots(idx, true))
	for i in _diff1p.size():
		var idx := i
		_diff1p[i].pressed.connect(func(): _set_diff(idx, true))
	for i in _win1p.size():
		var idx := i
		_win1p[i].pressed.connect(func(): _set_win(idx, true))
	_rounds_spin1p.value_changed.connect(func(v): _on_rounds_changed(v, true))

	for i in _bot2p.size():
		var idx := i
		_bot2p[i].pressed.connect(func(): _set_bots(idx, false))
	for i in _diff2p.size():
		var idx := i
		_diff2p[i].pressed.connect(func(): _set_diff(idx, false))
	for i in _win2p.size():
		var idx := i
		_win2p[i].pressed.connect(func(): _set_win(idx, false))
	_rounds_spin2p.value_changed.connect(func(v): _on_rounds_changed(v, false))
	
	$Center/Panel/VBox/BtnQuit.pressed.connect(get_tree().quit)
	_refresh_bots(true);  _refresh_bots(false)
	_refresh_diff(true);  _refresh_diff(false)
	_refresh_win(true);   _refresh_win(false)

	# --- NOWA LOGIKA QUIZÓW ---
	var quizzes = QuizManager.get_quiz_ids()
	_quiz_opt1p.add_item("Wszystkie")
	_quiz_opt2p.add_item("Wszystkie")
	for q in quizzes:
		_quiz_opt1p.add_item(q)
		_quiz_opt2p.add_item(q)

	_start1p.pressed.connect(func(): 
		var q_id = "" if _quiz_opt1p.selected <= 0 else _quiz_opt1p.get_item_text(_quiz_opt1p.selected)
		_start(1, _sel_bot_1p + 1, _sel_diff_1p, _sel_win_1p, int(_rounds_spin1p.value), q_id)
	)
	_start2p.pressed.connect(func(): 
		var q_id = "" if _quiz_opt2p.selected <= 0 else _quiz_opt2p.get_item_text(_quiz_opt2p.selected)
		_start(2, _sel_bot_2p, _sel_diff_2p, _sel_win_2p, int(_rounds_spin2p.value), q_id)
	)

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


func _set_win(idx: int, is_1p: bool) -> void:
	if is_1p: _sel_win_1p = idx
	else:      _sel_win_2p = idx
	_refresh_win(is_1p)


func _on_rounds_changed(value: float, is_1p: bool) -> void:
	## Aktualizuj label SpinBoxa w zależności od trybu
	var sel := _sel_win_1p if is_1p else _sel_win_2p
	var label := _rounds_label1p if is_1p else _rounds_label2p
	if sel == 0:
		label.text = "Wygrane rundy do zwycięstwa (X):"
	else:
		label.text = "Liczba rund w sesji (Y):"


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


func _refresh_win(is_1p: bool) -> void:
	var sel   := _sel_win_1p if is_1p else _sel_win_2p
	var btns  := _win1p      if is_1p else _win2p
	var label := _rounds_label1p if is_1p else _rounds_label2p
	for i in btns.size():
		btns[i].button_pressed = (i == sel)
	## Aktualizuj label przy zmianie trybu
	if sel == 0:
		label.text = "Wygrane rundy do zwycięstwa (X):"
	else:
		label.text = "Liczba rund w sesji (Y):"


func _start(humans: int, bots: int, diff: int, win_mode: int, rounds: int, quiz_id: String) -> void:
	GameManager.bot_difficulty = diff
	GameManager.win_condition  = win_mode as GameManager.WinCondition
	GameManager.selected_quiz_id = quiz_id
	
	if win_mode == GameManager.WinCondition.FIRST_TO_X:
		GameManager.rounds_to_win = rounds
	else:
		GameManager.max_rounds = rounds
	GameManager.start_game(humans, bots)
