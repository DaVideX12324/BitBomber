extends CanvasLayer

## Menu główne BitBomber.
## Jeden panel: wybor graczy (1-4) + boty (0 do 4-gracze) + trudnosc + tryb wygranej + Zagraj!
## Trudnosc ukryta gdy bots == 0.

@onready var _players_btns : Array[Button] = [
	$"Center/Panel/VBox/HBoxPlayers/Players_1",
	$"Center/Panel/VBox/HBoxPlayers/Players_2",
	$"Center/Panel/VBox/HBoxPlayers/Players_3",
	$"Center/Panel/VBox/HBoxPlayers/Players_4",
]
@onready var _bots_btns : Array[Button] = [
	$"Center/Panel/VBox/HBoxBots/Bots_0",
	$"Center/Panel/VBox/HBoxBots/Bots_1",
	$"Center/Panel/VBox/HBoxBots/Bots_2",
	$"Center/Panel/VBox/HBoxBots/Bots_3",
]
@onready var _diff_btns : Array[Button] = [
	$"Center/Panel/VBox/HBoxDiff/Diff_Easy",
	$"Center/Panel/VBox/HBoxDiff/Diff_Medium",
	$"Center/Panel/VBox/HBoxDiff/Diff_Hard",
]
@onready var _win_btns : Array[Button] = [
	$"Center/Panel/VBox/HBoxWin/Win_FirstTo",
	$"Center/Panel/VBox/HBoxWin/Win_MostWins",
]
@onready var _rounds_spin  : SpinBox      = $"Center/Panel/VBox/HBoxRounds/RoundsSpin"
@onready var _rounds_label : Label        = $"Center/Panel/VBox/HBoxRounds/RoundsLabel"
@onready var _diff_label   : Label        = $"Center/Panel/VBox/DiffLabel"
@onready var _diff_hbox    : HBoxContainer = $"Center/Panel/VBox/HBoxDiff"
@onready var _quiz_opt     : OptionButton = $"Center/Panel/VBox/QuizOpt"
@onready var _start_btn    : Button       = $"Center/Panel/VBox/BtnStart"

var _sel_players : int = 1  # 1-4
var _sel_bots    : int = 1  # 0-3
var _sel_diff    : int = 0
var _sel_win     : int = 0

var _help_overlay : ColorRect


func _ready() -> void:
	for i in _players_btns.size():
		var idx := i
		_players_btns[i].pressed.connect(func(): _set_players(idx + 1))

	for i in _bots_btns.size():
		var idx := i
		_bots_btns[i].pressed.connect(func(): _set_bots(idx))

	for i in _diff_btns.size():
		var idx := i
		_diff_btns[i].pressed.connect(func(): _set_diff(idx))

	for i in _win_btns.size():
		var idx := i
		_win_btns[i].pressed.connect(func(): _set_win(idx))

	_rounds_spin.value_changed.connect(_on_rounds_changed)
	_rounds_spin.get_line_edit().add_theme_font_size_override("font_size", 18)
	$Center/Panel/VBox/BtnQuit.pressed.connect(get_tree().quit)
	$Center/Panel/VBox/BtnHelp.pressed.connect(_show_help)

	var quizzes = QuizManager.get_quiz_ids()
	_quiz_opt.add_item("Wszystkie")
	for q in quizzes:
		_quiz_opt.add_item(q)

	_start_btn.pressed.connect(func():
		var q_id = "" if _quiz_opt.selected <= 0 else _quiz_opt.get_item_text(_quiz_opt.selected)
		_start(_sel_players, _sel_bots, _sel_diff, _sel_win, int(_rounds_spin.value), q_id)
	)

	_refresh_players()
	_refresh_bots()
	_refresh_diff()
	_refresh_win()

	_build_help_overlay()


# ---------------------------------------------------------------------------

func _set_players(count: int) -> void:
	_sel_players = count
	var max_bots := 4 - _sel_players
	var min_bots := 1 if _sel_players == 1 else 0
	_sel_bots = clampi(_sel_bots, min_bots, max_bots)
	_refresh_players()
	_refresh_bots()

func _set_bots(count: int) -> void:
	_sel_bots = count
	_refresh_bots()


func _set_diff(idx: int) -> void:
	_sel_diff = idx
	_refresh_diff()


func _set_win(idx: int) -> void:
	_sel_win = idx
	_refresh_win()


func _on_rounds_changed(value: float) -> void:
	if _sel_win == 0:
		_rounds_label.text = "Wygrane rundy do zwyci\u0119stwa (X):"
	else:
		_rounds_label.text = "Liczba rund w sesji (Y):"


func _refresh_players() -> void:
	for i in _players_btns.size():
		_players_btns[i].button_pressed = (i + 1 == _sel_players)


func _refresh_bots() -> void:
	var max_bots := 4 - _sel_players
	var min_bots := 1 if _sel_players == 1 else 0
	for i in _bots_btns.size():
		_bots_btns[i].disabled = (i > max_bots or i < min_bots)
		_bots_btns[i].button_pressed = (i == _sel_bots)


func _refresh_diff() -> void:
	for i in _diff_btns.size():
		_diff_btns[i].button_pressed = (i == _sel_diff)


func _refresh_win() -> void:
	for i in _win_btns.size():
		_win_btns[i].button_pressed = (i == _sel_win)
	if _sel_win == 0:
		_rounds_label.text = "Wygrane rundy do zwyci\u0119stwa (X):"
	else:
		_rounds_label.text = "Liczba rund w sesji (Y):"

func _start(humans: int, bots: int, diff: int, win_mode: int, rounds: int, quiz_id: String) -> void:
	GameManager.bot_difficulty   = diff
	GameManager.win_condition    = win_mode as GameManager.WinCondition
	GameManager.selected_quiz_id = quiz_id
	if win_mode == GameManager.WinCondition.FIRST_TO_X:
		GameManager.rounds_to_win = rounds
	else:
		GameManager.max_rounds = rounds
	GameManager.start_game(humans, bots)


# ---------------------------------------------------------------------------
# Instrukcja
# ---------------------------------------------------------------------------

func _build_help_overlay() -> void:
	_help_overlay = ColorRect.new()
	_help_overlay.color = Color(0, 0, 0, 0.75)
	_help_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_overlay.visible = false
	add_child(_help_overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640, 500)
	panel.offset_left   = -320
	panel.offset_top    = -250
	panel.offset_right  =  320
	panel.offset_bottom =  250
	_help_overlay.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "💣  Jak grać w BitBomber?"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content := RichTextLabel.new()
	content.bbcode_enabled = true
	content.fit_content = true
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_font_size_override("normal_font_size", 15)
	content.text = """[b]Cel gry[/b]
Wyeliminuj przeciwnik\u00f3w za pomoc\u0105 bomb! Ostatni \u017cywy gracz (lub ten z najwi\u0119ksz\u0105 liczb\u0105 wygranych rund) zdobywa zwyci\u0119stwo.

[b]Sterowanie \u2014 Gracz 1[/b]
  [b]WASD[/b]   ruch
  [b]Spacja[/b]   po\u0142\u00f3\u017c bomb\u0119

[b]Sterowanie \u2014 Gracz 2[/b]
  \u2191 \u2193 \u2190 \u2192   ruch
  [b]Enter / Num0[/b]   po\u0142\u00f3\u017c bomb\u0119

[b]Bomba[/b]
Wybucha po 2 sekundach. \u017c\u00f3\u0142knie od kraw\u0119dzi do \u015brodka \u2014 im bardziej \u017c\u00f3\u0142ta, tym bli\u017cej wybuchu.

[b]Power-upy[/b]
Pojawiaj\u0105 si\u0119 po zniszczeniu kruchych \u015bcian. Pop. odpowied\u017a na quiz = bonus.

[b]Last Chance[/b]
Po \u015bmierci gracza odpala si\u0119 quiz. Poprawna odpowied\u017a = respawn. B\u0142\u0119dna = koniec.

[b]Tryby wygranej[/b]
  [b]Pierwszy do X[/b]   wygrywa kto pierwszy zdoby\u0142 X wygranych rund
  [b]Najwi\u0119cej w Y[/b]   rozgrywanych jest Y rund, wygrywa kto ma wi\u0119cej zwyci\u0119stw

[b]Trudno\u015b\u0107 bota[/b]
  [b]\u0141atwy[/b]   bot reaguje wolno, proste pytania
  [b]\u015arednii[/b]   wywa\u017cony balans
  [b]Trudny[/b]   bot agresywny, trudniejsze pytania"""
	scroll.add_child(content)

	vbox.add_child(HSeparator.new())

	var btn_close := Button.new()
	btn_close.text = "Zamknij  [ESC]"
	btn_close.pressed.connect(_hide_help)
	vbox.add_child(btn_close)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _help_overlay and _help_overlay.visible:
		_hide_help()
		get_viewport().set_input_as_handled()


func _show_help() -> void:
	_help_overlay.visible = true


func _hide_help() -> void:
	_help_overlay.visible = false
