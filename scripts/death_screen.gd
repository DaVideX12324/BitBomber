extends CanvasLayer

## Death / Round-end / Game-over overlay.
##
## Tryby działania:
##   LAST_CHANCE  — gracz zginął, quiz daje szansę na respawn
##   ROUND_END    — runda skończyła się (można przejść dalej)
##   GAME_OVER    — cała sesja zakończona
##
## Kolejność sygnałów z RoundManagera:
##   round_ended  → _on_round_ended  → show_round_end  (BtnContinue widoczny)
##   session_ended→ _on_session_ended → show_game_over  (nadpisuje jeśli sesja się skończyła)

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
var _duel_allowed_types : Array[String] = []

var _duel_active    : bool = false
var _duel_p1_score  : int  = 0


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
	# Zmieniono 0 na 999
	if winner_id >= 1 or winner_id == 999:
		show_round_end(winner_id)
	else:
		show_round_end_draw()


func _on_session_ended(winner_id: int) -> void:
	show_game_over(winner_id)


# ---------------------------------------------------------------------------
# Quiz flow
# ---------------------------------------------------------------------------

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


func _get_weighted_question(allowed_types: Array = []) -> Dictionary:
	var range_v : Vector2i = _get_diff_range()
	var weights : Array[int]
	match GameManager.bot_difficulty:
		0: weights = [2, 3, 1]
		2: weights = [2, 3, 1]
		_: weights = [2, 3, 1]

	var all_ids : Array = []
	if GameManager.selected_quiz_id == "" or GameManager.selected_quiz_id == "Wszystkie":
		all_ids = QuizManager.get_quiz_ids()
	else:
		all_ids = [GameManager.selected_quiz_id]
	if all_ids.is_empty():
		return {}

	# 1. Zbieramy wszystkie poprawne typy i sprawdzamy dostępne trudności
	var valid_questions : Array = []
	var diffs_available : Array[int] = []
	
	for quiz_id in all_ids:
		for q in QuizManager._quizzes[quiz_id]:
			if not allowed_types.is_empty():
				var t = q.get("type", "multiple_choice")
				if not t in allowed_types:
					continue
			valid_questions.append(q)
			var d : int = q.get("difficulty", 1)
			if not d in diffs_available:
				diffs_available.append(d)

	if valid_questions.is_empty():
		return {}

	diffs_available.sort()
	var max_available_diff = diffs_available.back()

	# 2. FALLBACK: Jeśli JSON nie ma tak trudnych pytań, jakich wymaga poziom bota
	if max_available_diff < range_v.x:
		# Przesuwamy widełki szukania tak, by opierały się o najwyższą dostępną trudność
		range_v.y = max_available_diff
		range_v.x = maxi(1, max_available_diff - (weights.size() - 1))

	# 3. Losowanie z uwzględnieniem wag
	var pool : Array = []
	for q in valid_questions:
		var d : int = q.get("difficulty", 1)
		if d >= range_v.x and d <= range_v.y:
			var w_idx := d - range_v.x
			var w : int = weights[w_idx] if w_idx < weights.size() else 1
			for _i in range(w):
				pool.append(q)

	# 4. Zabezpieczenie ostateczne (np. jeśli pominąłeś jakąś trudność w środku JSON-a)
	if pool.is_empty():
		valid_questions.shuffle()
		return valid_questions[0]

	pool.shuffle()
	return pool[0]


func _is_simple_type(q: Dictionary) -> bool:
	var t : String = q.get("type", "multiple_choice")
	return t == "multiple_choice" or t == "true_false"


func _start_quiz_flow(dead_player_id: int) -> void:
	_duel_active   = false
	_duel_p1_score = 0
	_do_pause()

	var q := _get_weighted_question([])
	if q.is_empty():
		_on_quiz_result(1)
		return

	var two_player := GameManager.num_human_players >= 2
	var simple     := _is_simple_type(q)

	if simple:
		_duel_allowed_types = ["multiple_choice", "true_false"]
	else:
		_duel_allowed_types = ["fill_tiles", "fill_text", "matching"]

	QuizManager._current_questions = [q]
	QuizManager._current_question_index = 0

# Domyślnie zakładamy tryb 1P (SOLO)
	var mode = _quiz_overlay.RivalMode.SOLO
	
	# Jeśli gramy w 2 osoby, włączamy mechaniki rywalizacji
	if two_player:
		if simple:
			mode = _quiz_overlay.RivalMode.VERSUS
		else:
			if dead_player_id == 2:
				mode = _quiz_overlay.RivalMode.DUEL_P2 
			else:
				mode = _quiz_overlay.RivalMode.DUEL_P1

	_quiz_overlay.show_quiz(q, mode, _get_time_limit(), dead_player_id)


func _ask_question_p1() -> void:
	var q := _get_weighted_question(_duel_allowed_types)
	if q.is_empty():
		_on_quiz_result(1)
		return
	QuizManager._current_questions = [q]
	QuizManager._current_question_index = 0
	_quiz_overlay.show_quiz(q, _quiz_overlay.RivalMode.DUEL_P1, _get_time_limit(), _dead_player_id)


func _ask_question_p2() -> void:
	var q := _get_weighted_question(_duel_allowed_types)
	if q.is_empty():
		_on_quiz_result(1)
		return
	QuizManager._current_questions = [q]
	QuizManager._current_question_index = 0
	_quiz_overlay.show_quiz(q, _quiz_overlay.RivalMode.DUEL_P2, _get_time_limit(), _dead_player_id)


# ---------------------------------------------------------------------------
# Wynik quizu
# ---------------------------------------------------------------------------

func _on_quiz_result(winner_id: int) -> void:
	match [_dead_player_id, winner_id]:
		# --- ROZSTRZYGNIĘCIA OSTATECZNE (Ktoś wygrał / przegrał) ---
		[1, 1]:
			_duel_active = false
			_do_resume()
			RoundManager.resolve_last_chance(true)
		[1, 2]:
			_duel_active = false
			_do_resume()
			RoundManager.resolve_last_chance(false)
		[2, 2]:
			_duel_active = false
			_do_resume()
			RoundManager.resolve_last_chance(true)
		[2, 1]:
			_duel_active = false
			_do_resume()
			RoundManager.resolve_last_chance(false)
			
		# --- KONTYNUACJA POJEDYNKU (Tura drugiego gracza) ---
		[1, 0]: # P1 (martwy) odpowiedział poprawnie, teraz kolej P2 by się obronić
			_duel_active = true
			_ask_question_p2()
		[2, 3]: # P2 (martwy) odpowiedział poprawnie, teraz kolej P1 by się obronić
			_duel_active = true
			_ask_question_p1()
			
		# --- REMIS PO PEŁNYM CYKLU (Obaj odpowiedzieli poprawnie) ---
		[1, 3], [2, 0]:
			# Pełen cykl zakończony. Zamiast ciągnąć stary typ pytań w nieskończoność,
			# restartujemy całą mechanikę od zera. Gra wylosuje nowe pytanie 
			# ze wszystkich dostępnych typów (może to być VERSUS lub nowy DUEL)!
			_start_quiz_flow(_dead_player_id)

# ---------------------------------------------------------------------------
# Show helpers
# ---------------------------------------------------------------------------


func show_round_end(winner_id: int) -> void:
	_mode = Mode.ROUND_END
	_icon.text = "🏁"
	
	if winner_id == 999: # Zmieniono 0 na 999
		_title.text = "Boty wygrały rundę %d!" % RoundManager.current_round
	else:
		_title.text = "Gracz %d wygrał rundę %d!" % [winner_id, RoundManager.current_round]
		
	_subtitle.text = _build_score_text()
	_btn_cont.text = _next_round_label()
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()
	_do_pause()

func show_round_end_draw() -> void:
	_mode = Mode.ROUND_END
	_icon.text = "⏳"
	_title.text = "Remis w rundzie %d!" % RoundManager.current_round
	_subtitle.text = _build_score_text()
	_btn_cont.text = _next_round_label()
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()
	_do_pause()


func show_game_over(winner_id: int) -> void:
	_mode = Mode.GAME_OVER
	
	if winner_id == -1:
		_icon.text = "🤝"
		_title.text = "Remis!"
		_subtitle.text = "Obaj gracze zginęli jednocześnie."
	elif winner_id == 999: # Zmieniono 0 na 999
		_icon.text = "🤖"
		_title.text = "Wygrały boty!"
		_subtitle.text = "Lepiej następnym razem."
	else:
		_icon.text = "🏆"
		_title.text = "Gracz %d wygrał!" % winner_id
		
	_subtitle.text = _build_score_text()
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
			GameManager.change_state(GameManager.GameState.PLAYING)
			if GameManager.game_node:
				GameManager.game_node.next_round()
		Mode.GAME_OVER:
			pass


func _on_menu() -> void:
	_do_resume()
	_hide()
	GameManager.go_to_menu()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _next_round_label() -> String:
	var rem := RoundManager.rounds_remaining()
	match GameManager.win_condition:
		GameManager.WinCondition.FIRST_TO_X:
			return "Następna runda (lider potrzebuje jeszcze %d)" % rem
		GameManager.WinCondition.MOST_WINS_IN_Y:
			if rem > 0:
				return "Następna runda (%d pozostało)" % rem
			else:
				return "Ostatnia runda!"
		_:
			return "Następna runda"


func _build_score_text() -> String:
	var lines : PackedStringArray = []
	
	for pid in range(1, GameManager.num_human_players + 1):
		var w := RoundManager.get_wins(pid)
		lines.append("Gracz %d: %d wygranych rund" % [pid, w])
		
	if GameManager.num_bots > 0:
		# ZMIANA: Pobieramy wygrane zespołowe spod ID 999
		var bot_wins := RoundManager.get_wins(999) 
		
		for b in range(GameManager.num_bots):
			var bot_pid = GameManager.num_human_players + b + 1
			bot_wins += RoundManager.get_wins(bot_pid)
			
		lines.append("Boty: %d wygranych rund" % bot_wins)
		
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
