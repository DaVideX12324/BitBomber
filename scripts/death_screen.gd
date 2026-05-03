extends CanvasLayer

## Death / Round-end / Game-over overlay.
##
## Tryby działania:
##   LAST_CHANCE  — gracz zginął, quiz daje szansę na respawn
##   ROUND_END    — runda skończyła się
##   GAME_OVER    — cała sesja zakończona
##
## Quiz wbudowany jako sub-flow przed decyzją o respawnie.

enum Mode { LAST_CHANCE, ROUND_END, GAME_OVER }

@onready var _overlay   : ColorRect      = $Overlay
@onready var _panel     : PanelContainer = $Panel
@onready var _icon      : Label          = $Panel/VBox/Icon
@onready var _title     : Label          = $Panel/VBox/Title
@onready var _subtitle  : Label          = $Panel/VBox/Subtitle
@onready var _quiz_slot : VBoxContainer  = $Panel/VBox/QuizSlot
@onready var _btn_cont  : Button         = $Panel/VBox/Buttons/BtnContinue
@onready var _btn_menu  : Button         = $Panel/VBox/Buttons/BtnMenu
@onready var _quiz_overlay : CanvasLayer = $QuizOverlay

var _mode           : Mode = Mode.ROUND_END
var _dead_player_id : int  = -1

# Stan turnieju quizowego (tryb 2P, pytania złożone)
var _duel_active    : bool = false
var _duel_p1_score  : int  = 0   # ile razy P1 odpowiedział poprawnie z rzędu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_btn_cont.pressed.connect(_on_continue)
	_btn_menu.pressed.connect(_on_menu)
	RoundManager.last_chance_triggered.connect(_on_last_chance)
	RoundManager.round_ended.connect(_on_round_ended)
	RoundManager.session_ended.connect(_on_session_ended)
	_quiz_overlay.quiz_result.connect(_on_quiz_result)
	_quiz_overlay.visible = false


# ---------------------------------------------------------------------------
# Sygnały z RoundManagera
# ---------------------------------------------------------------------------

func _on_last_chance(dead_player_id: int) -> void:
	_dead_player_id = dead_player_id
	_start_quiz_flow(dead_player_id)


func _on_round_ended(winner_id: int) -> void:
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return
	if winner_id >= 1:
		show_round_end(winner_id)
	else:
		show_round_end_draw()


func _on_session_ended(winner_id: int) -> void:
	show_game_over(winner_id)


# ---------------------------------------------------------------------------
# Quiz flow
# ---------------------------------------------------------------------------

func _start_quiz_flow(dead_player_id: int) -> void:
	_duel_active   = false
	_duel_p1_score = 0
	_do_pause()
	_ask_question_p1()


func _get_time_limit() -> float:
	match GameManager.bot_difficulty:
		0: return 20.0
		2: return 10.0
		_: return 15.0


func _get_diff_range() -> Vector2i:
	match GameManager.bot_difficulty:
		0: return Vector2i(1, 3)
		2: return Vector2i(3, 5)
		_: return Vector2i(2, 4)


func _get_weighted_question() -> Dictionary:
	var range_v : Vector2i = _get_diff_range()  # ← dodaj tę linię
	# wagi: [najczęstsza, średnia, rzadka] dla diff base, base+1, base+2
	var weights : Array[int]
	match GameManager.bot_difficulty:
		0: weights = [2, 3, 1]   # diff 1,2,3
		2: weights = [2, 3, 1]   # diff 3,4,5
		_: weights = [2, 3, 1]   # diff 2,3,4

	var pool : Array = []
	var all_ids := QuizManager.get_quiz_ids()
	if all_ids.is_empty():
		return {}

	for quiz_id in all_ids:
		for q in QuizManager._quizzes[quiz_id]:
			var d : int = q.get("difficulty", 1)
			if d < range_v.x or d > range_v.y:
				continue
			var w_idx := d - range_v.x
			var w : int = weights[w_idx] if w_idx < weights.size() else 1
			for _i in range(w):
				pool.append(q)

	if pool.is_empty():
		return {}
	pool.shuffle()
	return pool[0]


func _is_simple_type(q: Dictionary) -> bool:
	var t : String = q.get("type", "multiple_choice")
	return t == "multiple_choice" or t == "true_false"


func _ask_question_p1() -> void:
	var q := _get_weighted_question()
	if q.is_empty():
		# Brak pytań — daj respawn z automatu
		_on_quiz_result(1)
		return

	var two_player := GameManager.num_human_players >= 2
	var simple     := _is_simple_type(q)

	QuizManager.start_quiz(
		q.get("_quiz_id", QuizManager.get_quiz_ids()[0]),
		_get_diff_range(), 1, []
	)
	# Nadpisz bieżące pytanie bezpośrednio (start_quiz losuje, chcemy konkretne)
	QuizManager._current_questions = [q]
	QuizManager._current_question_index = 0

	if two_player and simple:
		_quiz_overlay.show_quiz(q, _quiz_overlay.RivalMode.VERSUS, _get_time_limit())
	else:
		_quiz_overlay.show_quiz(q, _quiz_overlay.RivalMode.DUEL_P1, _get_time_limit())


func _ask_question_p2() -> void:
	var q := _get_weighted_question()
	if q.is_empty():
		# Brak pytań — P2 "odpada" → P1 wygrywa (respawn)
		_on_quiz_result(1)
		return

	QuizManager._current_questions = [q]
	QuizManager._current_question_index = 0

	_quiz_overlay.show_quiz(q, _quiz_overlay.RivalMode.DUEL_P2, _get_time_limit())


# ---------------------------------------------------------------------------
# Wynik quizu
# ---------------------------------------------------------------------------
# winner_id:
#   1  — P1 wygrał tę rundę quizową (respawn lub P2 odpada)
#   2  — P2 wygrał / P1 odpada
#   0  — P2 odpowiedział poprawnie → turniej trwa, kolej P1

func _on_quiz_result(winner_id: int) -> void:
	var two_player := GameManager.num_human_players >= 2

	if winner_id == 1:
		# P1 respawn — koniec quizu
		_duel_active = false
		_do_resume()
		RoundManager.resolve_last_chance(true)
		return

	if winner_id == 2:
		if two_player:
			# P2 wygrywa całą sesję
			_duel_active = false
			show_game_over(2)
		else:
			# Solo — P1 odpada (bot wygrywa)
			_duel_active = false
			show_game_over(0)
		return

	if winner_id == 0:
		# Tryb turnieju: P2 odpowiedział poprawnie → P1 musi znowu
		_duel_active = true
		_ask_question_p1()


# ---------------------------------------------------------------------------
# Show helpers
# ---------------------------------------------------------------------------

func show_round_end(winner_id: int) -> void:
	_mode = Mode.ROUND_END
	_icon.text = "🏆"
	_title.text = "Gracz %d wygrał rundę!" % winner_id
	_subtitle.text = _build_score_text()
	_btn_cont.text = "Następna runda"
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()
	_do_pause()


func show_round_end_draw() -> void:
	_mode = Mode.ROUND_END
	_icon.text = "⏳"
	_title.text = "Remis!"
	_subtitle.text = _build_score_text()
	_btn_cont.text = "Następna runda"
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()
	_do_pause()


func show_game_over(winner_id: int) -> void:
	_mode = Mode.GAME_OVER
	if winner_id == -1:
		_icon.text = "⏳"
		_title.text = "Remis!"
		_subtitle.text = "Obaj gracze zginęli jednocześnie."
	elif winner_id == 0:
		_icon.text = "🤖"
		_title.text = "Wygrał bot!"
		_subtitle.text = "Lepiej następnym razem."
	else:
		_icon.text = "🏆"
		_title.text = "Gracz %d wygrał!" % winner_id
		_subtitle.text = "Gratulacje!"
	_btn_cont.visible = false
	_btn_menu.visible = true
	_btn_menu.text = "Menu główne"
	_show()
	_do_pause()


# ---------------------------------------------------------------------------
# Pauza / wznowienie
# ---------------------------------------------------------------------------

func _do_pause() -> void:
	get_tree().paused = true


func _do_resume() -> void:
	get_tree().paused = false


# ---------------------------------------------------------------------------
# Przyciski
# ---------------------------------------------------------------------------

func _on_continue() -> void:
	match _mode:
		Mode.ROUND_END:
			_do_resume()
			_hide()
			if GameManager.game_node:
				GameManager.game_node.load_arena()
			GameManager.change_state(GameManager.GameState.PLAYING)
		Mode.GAME_OVER:
			pass


func _on_menu() -> void:
	_do_resume()
	_hide()
	GameManager.go_to_menu()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _build_score_text() -> String:
	var lines : PackedStringArray = []
	for pid : int in [1, 2]:
		var w := RoundManager.get_wins(pid)
		lines.append("Gracz %d: %d rund" % [pid, w])
	return "\n".join(lines)


func _show() -> void:
	visible = true
	_overlay.modulate.a = 0.0
	_panel.modulate.a   = 0.0
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.25)


func _hide() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(_panel, "modulate:a", 0.0, 0.2)
	await tw.finished
	visible = false
	_quiz_slot.visible = false
	_btn_cont.visible  = true
	_btn_menu.visible  = true
