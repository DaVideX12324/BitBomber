extends CanvasLayer

## Menu główne BitBomber.

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
@onready var _rounds_spin    : SpinBox        = $"Center/Panel/VBox/HBoxRounds/RoundsSpin"
@onready var _rounds_label   : Label          = $"Center/Panel/VBox/HBoxRounds/RoundsLabel"
@onready var _diff_label     : Label          = $"Center/Panel/VBox/DiffLabel"
@onready var _diff_hbox      : HBoxContainer  = $"Center/Panel/VBox/HBoxDiff"
@onready var _quiz_opt       : OptionButton   = $"Center/Panel/VBox/QuizOpt"
@onready var _start_btn      : Button         = $"Center/Panel/VBox/BtnStart"
@onready var _btn_quit       : Button         = $"Center/Panel/VBox/BtnQuit"
@onready var _btn_help       : Button         = $"Center/Panel/VBox/HBoxMeta/BtnHelp"
@onready var _btn_options    : Button         = $"Center/Panel/VBox/HBoxMeta/BtnOptions"
@onready var _options_menu                    = $OptionsMenu

var _sel_players : int = 1
var _sel_bots    : int = 1
var _sel_diff    : int = 0
var _sel_win     : int = 0

var _help_overlay  : ColorRect
var _help_title    : Label
var _help_content  : RichTextLabel
var _help_close    : Button


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
	_btn_quit.pressed.connect(get_tree().quit)
	_btn_help.pressed.connect(_show_help)
	_btn_options.pressed.connect(func(): _options_menu.open())
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
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


func _on_scale_changed(_s: float) -> void:
	var fs_btn   := UIScaleManager.px(22)
	var fs_label := UIScaleManager.px(18)
	var fs_meta  := UIScaleManager.px(16)
	# Przyciski wyboru (gracze / boty / trudność / wygrana)
	for btn: Button in _players_btns + _bots_btns + _diff_btns + _win_btns:
		btn.add_theme_font_size_override("font_size", fs_btn)
	# Przyciski główne
	_start_btn.add_theme_font_size_override("font_size", UIScaleManager.px(26))
	_btn_quit.add_theme_font_size_override("font_size", fs_meta)
	_btn_help.add_theme_font_size_override("font_size", fs_meta)
	_btn_options.add_theme_font_size_override("font_size", fs_meta)
	# Labele
	_rounds_label.add_theme_font_size_override("font_size", fs_label)
	_diff_label.add_theme_font_size_override("font_size", fs_label)
	# SpinBox
	_rounds_spin.get_line_edit().add_theme_font_size_override("font_size", fs_label)
	# OptionButton (quiz)
	_quiz_opt.add_theme_font_size_override("font_size", fs_label)
	# Overlay pomocy (jeśli już zbudowany)
	if _help_title:
		_help_title.add_theme_font_size_override("font_size", UIScaleManager.px(22))
	if _help_content:
		_help_content.add_theme_font_size_override("normal_font_size", UIScaleManager.px(15))
	if _help_close:
		_help_close.add_theme_font_size_override("font_size", fs_meta)


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


func _on_rounds_changed(_value: float) -> void:
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
# Instrukcja (budowana dynamicznie)
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

	_help_title = Label.new()
	_help_title.text = "\U0001F4A3  Jak gra\u0107 w BitBomber?"
	_help_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_help_title)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_help_content = RichTextLabel.new()
	_help_content.bbcode_enabled = true
	_help_content.fit_content = true
	_help_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_content.text = """[b]Cel gry[/b]
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
	scroll.add_child(_help_content)

	vbox.add_child(HSeparator.new())
	_help_close = Button.new()
	_help_close.text = "Zamknij  [ESC]"
	_help_close.pressed.connect(_hide_help)
	vbox.add_child(_help_close)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _help_overlay and _help_overlay.visible:
		_hide_help()
		get_viewport().set_input_as_handled()


func _show_help() -> void:
	_help_overlay.visible = true


func _hide_help() -> void:
	_help_overlay.visible = false
