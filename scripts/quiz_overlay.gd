extends CanvasLayer

## Quiz Overlay — wyświetla pytanie quizowe podczas "ostatniej szansy".
##
## Tryby rywalizacji:
##   SOLO       — tylko gracz 1 odpowiada (1P lub pytanie złożone w 2P)
##   VERSUS     — obaj gracze odpowiadają jednocześnie (multiple_choice / true_false w 2P)
##   DUEL_P1    — turniej: teraz odpowiada Gracz 1
##   DUEL_P2    — turniej: teraz odpowiada Gracz 2
##
## Sygnały:
##   quiz_result(winner_id)
##     1  = P1 respawn
##     2  = P2 wygrywa / P1 odpada
##     0  = P2 odpowiedział poprawnie → turniej trwa, kolej P1

signal quiz_result(winner_id: int)

enum RivalMode { SOLO, VERSUS, DUEL_P1, DUEL_P2 }

# ─────────────────────────────────────────────────────────────────────────────
# Stałe do obliczania czasu
# ─────────────────────────────────────────────────────────────────────────────

## Sekund na jedno słowo (czas na przeczytanie pytania + odpowiedzi).
const WORDS_PER_SEC : float = 0.35

## Mnożniki czasu odpowiedzi per typ pytania.
## true_false jest krótkie z natury, matching wymaga analizy par.
const TYPE_MULTIPLIER : Dictionary = {
	"true_false":      0.70,
	"multiple_choice": 1.00,
	"fill_text":       1.20,
	"fill_tiles":      1.40,
	"matching":        1.55,
}

## Ile sekund na diff zmienia się czas względem diff bazowego.
## base_difficulty = poziom wybrany przez gracza (środek puli).
## Każdy krok różnicy ±1 od bazy = ±DIFF_STEP_SEC sekund.
const DIFF_STEP_SEC : float = 3.0


# ─────────────────────────────────────────────────────────────────────────────
# Publiczna funkcja pomocnicza — oblicz czas dla pytania
# ─────────────────────────────────────────────────────────────────────────────

## Oblicza ostateczny limit czasu dla pytania.
##
## [param question]        Słownik pytania z JSON-a.
## [param base_time]       Bazowy czas (w sekundach) dla base_difficulty.
## [param base_difficulty] Środkowy poziom trudności wybrany przez gracza (np. 3 dla medium).
##
## Formuła:
##   1. word_bonus  = liczba słów we wszystkich tekstach pytania × WORDS_PER_SEC
##   2. type_mult   = TYPE_MULTIPLIER[question.type]
##   3. diff_offset = (question.difficulty − base_difficulty) × DIFF_STEP_SEC
##   4. result      = (base_time + word_bonus) × type_mult + diff_offset
##   Wynik jest clampowany do [5.0, 120.0].
static func calculate_time(question: Dictionary, base_time: float, base_difficulty: int) -> float:
	# 1. Zlicz słowa we wszystkich polach tekstowych pytania
	var word_count : int = 0
	var text_fields : Array[String] = [
		question.get("question", ""),
		question.get("statement", ""),
		question.get("prompt", ""),
		question.get("text_with_gaps", ""),
	]
	for field : String in text_fields:
		if field != "":
			word_count += field.split(" ", false).size()

	# Odpowiedzi (multiple_choice)
	var answers : Array = question.get("answers", [])
	for ans in answers:
		word_count += str(ans).split(" ", false).size()

	# left_items / right_items (matching)
	var left_items : Array = question.get("left_items", [])
	var right_items : Array = question.get("right_items", [])
	for item in left_items:
		word_count += str(item).split(" ", false).size()
	for item in right_items:
		word_count += str(item).split(" ", false).size()

	# 2. Bonus za czytanie
	var word_bonus : float = float(word_count) * WORDS_PER_SEC

	# 3. Mnożnik typu pytania
	var qtype : String = question.get("type", "multiple_choice")
	var type_mult : float = TYPE_MULTIPLIER.get(qtype, 1.0)

	# 4. Offset za trudność (diff pytania vs diff bazowy gracza)
	var q_diff : int = question.get("difficulty", base_difficulty)
	var diff_offset : float = float(q_diff - base_difficulty) * DIFF_STEP_SEC

	# 5. Sklejenie
	var result : float = (base_time + word_bonus) * type_mult + diff_offset
	return clampf(result, 5.0, 120.0)


@onready var _overlay      : ColorRect      = $Overlay
@onready var _panel        : PanelContainer = $Panel
@onready var _vbox         : VBoxContainer  = $Panel/VBox
@onready var _lbl_title    : Label          = $Panel/VBox/Title
@onready var _lbl_question : Label          = $Panel/VBox/Question
@onready var _lbl_timer    : Label          = $Panel/VBox/Timer
@onready var _lbl_hint     : Label          = $Panel/VBox/Hint
@onready var _answers_box  : VBoxContainer  = $Panel/VBox/AnswersBox
@onready var _timer_node   : Timer          = $Timer

var _question      : Dictionary = {}
var _mode          : RivalMode  = RivalMode.SOLO
var _time_left     : float      = 15.0
var _total_time    : float      = 15.0
var _answered_p1   : bool       = false
var _answered_p2   : bool       = false
var _correct_p1    : bool       = false
var _correct_p2    : bool       = false
var _locked        : bool       = false
var current_dead_player: int = 0

# fill_tiles
var _tile_slots    : Array[String]  = []
var _tile_buttons  : Array[Button]  = []
var _gap_labels    : Array[Button]  = []
var _active_gap    : int            = 0

# matching
var _match_selected  : int              = -1
var _match_pairs     : Dictionary       = {}
var _match_left_btns : Array[Button]    = []
var _match_right_btns: Array[Button]    = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_timer_node.timeout.connect(_on_timer_timeout)
	_locked = false
	# Włącz zawijanie tekstu pytania + rozciągnięcie na całą szerokość
	_lbl_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_question.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# ─────────────────────────────────────────────────────────────────────────────
# Publiczne API
# ─────────────────────────────────────────────────────────────────────────────

func show_quiz(question: Dictionary, rival_mode: RivalMode, time_limit: float, dead_pid: int = 0) -> void:
	_question    = question
	_mode        = rival_mode
	_time_left   = time_limit
	_total_time  = time_limit
	current_dead_player = dead_pid
	
	_dbg("--- START --- Typ: %s" % question.get("type", "unknown"))
	
	_answered_p1 = false
	_answered_p2 = false
	_correct_p1  = false
	_correct_p2  = false
	
	_tile_slots.clear()
	_tile_buttons.clear()
	_gap_labels.clear()
	_active_gap   = 0
	
	_match_selected = -1
	_match_pairs.clear()
	_match_left_btns.clear()
	_match_right_btns.clear()
	
	_build_ui()
	visible = true
	_timer_node.wait_time = time_limit
	_timer_node.start()
	var qtype : String = _question.get("type", "multiple_choice")
	_locked = (qtype == "multiple_choice" or qtype == "true_false")
	if _locked:
		get_tree().create_timer(0.5).timeout.connect(func(): _locked = false)
	_locked = false


func _dbg(msg: String) -> void:
	if GameManager.debug_enabled:
		var mode_str = RivalMode.keys()[_mode]
		print("[QUIZ | %s | Dead:P%d] %s" % [mode_str, current_dead_player, msg])


# ─────────────────────────────────────────────────────────────────────────────
# Budowanie UI
# ─────────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	for ch in _answers_box.get_children():
		ch.queue_free()

	var qtype : String = _question.get("type", "multiple_choice")

	match _mode:
		RivalMode.SOLO:    _lbl_title.text = "⚡ Ostatnia szansa – Gracz 1"
		RivalMode.VERSUS:  _lbl_title.text = "⚡ Rywalizacja!"
		RivalMode.DUEL_P1: _lbl_title.text = "⚡ Kolej Gracza 1"
		RivalMode.DUEL_P2: _lbl_title.text = "⚡ Kolej Gracza 2"

	match qtype:
		"true_false": _lbl_question.text = _question.get("statement", "")
		"fill_text":  _lbl_question.text = _question.get("prompt", "")
		_:            _lbl_question.text = _question.get("question", _question.get("prompt", ""))

	match qtype:
		"multiple_choice", "true_false":
			if _mode == RivalMode.VERSUS:
				_lbl_hint.text = "P1: W/S/A/D  |  P2: ↑↓←→"
			elif _mode == RivalMode.DUEL_P2:
				_lbl_hint.text = "P2: ↑↓←→  lub  LPM"
			else:
				_lbl_hint.text = "P1: W/S/A/D  lub  LPM"
		"fill_text":
			if _mode == RivalMode.DUEL_P2:
				_lbl_hint.text = "P2: wpisz odpowiedź – Enter aby zatwierdzić"
			else:
				_lbl_hint.text = "P1: wpisz odpowiedź – Enter aby zatwierdzić"
		"fill_tiles":
			_lbl_hint.text = "Kliknij kafelek aby wypełnić lukę | Tab – zmień lukę"
		"matching":
			_lbl_hint.text = "Kliknij element po lewej, potem po prawej | Enter – zatwierdź"

	match qtype:
		"multiple_choice": _build_mc()
		"true_false":       _build_tf()
		"fill_tiles":       _build_fill_tiles()
		"fill_text":        _build_fill_text()
		"matching":         _build_matching()


func _build_mc() -> void:
	var answers : Array = _question.get("answers", [])
	var keys_p1 : Array[String] = ["W", "S", "A", "D"]
	var keys_p2 : Array[String] = ["↑", "↓", "←", "→"]
	for i in range(answers.size()):
		var btn := Button.new()
		var answer_text : String = str(answers[i])
		var k1 : String = keys_p1[i] if i < 4 else "?"
		var k2 : String = keys_p2[i] if i < 4 else "?"
		if _mode == RivalMode.VERSUS:
			btn.text = "[%s/%s]  %s" % [k1, k2, answer_text]
		elif _mode == RivalMode.DUEL_P2:
			btn.text = "[%s]  %s" % [k2, answer_text]
		else:
			btn.text = "[%s]  %s" % [k1, answer_text]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_mc_button.bind(i))
		_answers_box.add_child(btn)


func _build_tf() -> void:
	var labels : Array[String] = ["Prawda", "Fałsz"]
	var k1     : Array[String] = ["W", "S"]
	var k2     : Array[String] = ["↑", "↓"]
	for i in range(2):
		var btn := Button.new()
		if _mode == RivalMode.VERSUS:
			btn.text = "[%s/%s]  %s" % [k1[i], k2[i], labels[i]]
		elif _mode == RivalMode.DUEL_P2:
			btn.text = "[%s]  %s" % [k2[i], labels[i]]
		else:
			btn.text = "[%s]  %s" % [k1[i], labels[i]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_tf_button.bind(i == 0))
		_answers_box.add_child(btn)


func _build_fill_tiles() -> void:
	var text_with_gaps : String = _question.get("text_with_gaps", "")
	var gaps           : Array  = _question.get("gaps", [])
	var tiles          : Array  = _question.get("tiles", [])

	_tile_slots.resize(gaps.size())
	_tile_slots.fill("")

	# HFlowContainer zamiast HBoxContainer — automatycznie zalega do nowej linii
	var hbox_text := HFlowContainer.new()
	hbox_text.add_theme_constant_override("separation", 4)
	hbox_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answers_box.add_child(hbox_text)

	var parts : PackedStringArray = text_with_gaps.split("___")
	for i in range(parts.size()):
		var lbl := Label.new()
		lbl.text = parts[i]
		hbox_text.add_child(lbl)
		if i < gaps.size():
			var gap_btn := Button.new()
			gap_btn.focus_mode = Control.FOCUS_NONE
			gap_btn.custom_minimum_size = Vector2(120, 36)
			gap_btn.text = "[ ___ ]"
			gap_btn.pressed.connect(_on_gap_clicked.bind(i))
			hbox_text.add_child(gap_btn)
			_gap_labels.append(gap_btn)

	var sep := HSeparator.new()
	_answers_box.add_child(sep)
	var tile_box := HFlowContainer.new()
	tile_box.add_theme_constant_override("separation", 6)
	_answers_box.add_child(tile_box)

	for tile in tiles:
		var tbtn := Button.new()
		tbtn.text = str(tile)
		tbtn.focus_mode = Control.FOCUS_NONE
		tbtn.pressed.connect(_on_tile_clicked.bind(str(tile), tbtn))
		tile_box.add_child(tbtn)
		_tile_buttons.append(tbtn)

	var confirm := Button.new()
	confirm.text = "✔ Zatwierdź (Enter)"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_on_fill_tiles_confirm)
	_answers_box.add_child(confirm)

	_update_gap_highlight()


func _build_fill_text() -> void:
	var pattern : String = _question.get("prefilled_pattern", "")
	if pattern != "":
		var hint_lbl := Label.new()
		hint_lbl.text = "Podpowiedź: %s" % pattern
		hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_answers_box.add_child(hint_lbl)

	var line_edit := LineEdit.new()
	line_edit.name = "FillTextInput"
	line_edit.placeholder_text = "Wpisz odpowiedź…"
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answers_box.add_child(line_edit)
	line_edit.grab_focus()
	line_edit.text_submitted.connect(func(text): _on_fill_text_confirm())
	var confirm := Button.new()
	confirm.text = "✔ Zatwierdź (Enter)"
	confirm.pressed.connect(_on_fill_text_confirm)
	_answers_box.add_child(confirm)


func _build_matching() -> void:
	var left_items  : Array = _question.get("left_items", [])
	var right_items : Array = _question.get("right_items", [])

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answers_box.add_child(grid)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(left_col)
	for i in range(left_items.size()):
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = str(left_items[i])
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_match_left.bind(i))
		left_col.add_child(btn)
		_match_left_btns.append(btn)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(right_col)
	for i in range(right_items.size()):
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = str(right_items[i])
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_match_right.bind(i))
		right_col.add_child(btn)
		_match_right_btns.append(btn)

	var confirm := Button.new()
	confirm.text = "✔ Zatwierdź (Enter)"
	confirm.pressed.connect(_on_matching_confirm)
	_answers_box.add_child(confirm)


# ─────────────────────────────────────────────────────────────────────────────
# Input klawiaturowy
# ─────────────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var qtype : String = _question.get("type", "multiple_choice")

	if qtype == "multiple_choice" or qtype == "true_false":
		_handle_key_choice(event)
	elif qtype == "fill_tiles":
		if event is InputEventKey and event.pressed:
			var ke := event as InputEventKey
			if ke.keycode == KEY_TAB:
				_active_gap = (_active_gap + 1) % max(_tile_slots.size(), 1)
				_update_gap_highlight()
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				_on_fill_tiles_confirm()
				get_viewport().set_input_as_handled()
	elif qtype == "fill_text":
		pass  
	elif qtype == "matching":
		if event is InputEventKey and event.pressed:
			var ke := event as InputEventKey
			if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				_on_matching_confirm()
				get_viewport().set_input_as_handled()


func _handle_key_choice(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).is_echo():
		return
	var ke := event as InputEventKey
	var qtype : String = _question.get("type", "multiple_choice")
	var answers_count : int
	if qtype == "multiple_choice":
		answers_count = (_question.get("answers", []) as Array).size()
	else:
		answers_count = 2

	var p1_keys : Array[Key] = [KEY_W, KEY_S, KEY_A, KEY_D]
	var p2_keys : Array[Key] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]

	for i in range(min(answers_count, 4)):
		if _mode in [RivalMode.SOLO, RivalMode.VERSUS, RivalMode.DUEL_P1]:
			if ke.keycode == p1_keys[i] and not _answered_p1:
				_submit_answer(1, i)
				get_viewport().set_input_as_handled()
				return
		if _mode in [RivalMode.VERSUS, RivalMode.DUEL_P2]:
			if ke.keycode == p2_keys[i] and not _answered_p2:
				_submit_answer(2, i)
				get_viewport().set_input_as_handled()
				return


# ─────────────────────────────────────────────────────────────────────────────
# Obsługa przycisków
# ─────────────────────────────────────────────────────────────────────────────

func _on_mc_button(index: int) -> void:
	if _mode == RivalMode.DUEL_P2:
		if not _answered_p2: _submit_answer(2, index)
	else:
		if not _answered_p1: _submit_answer(1, index)


func _on_tf_button(value: bool) -> void:
	var idx : int = 0 if value else 1
	if _mode == RivalMode.DUEL_P2:
		if not _answered_p2: _submit_answer(2, idx)
	else:
		if not _answered_p1: _submit_answer(1, idx)


func _on_gap_clicked(gap_index: int) -> void:
	_active_gap = gap_index
	_update_gap_highlight()


func _on_tile_clicked(tile_text: String, tile_btn: Button) -> void:
	if _tile_slots.size() == 0:
		return
	var old_tile : String = _tile_slots[_active_gap]
	if old_tile != "":
		for tbtn : Button in _tile_buttons:
			if tbtn.text == old_tile:
				tbtn.disabled = false
				break
	_tile_slots[_active_gap] = tile_text
	tile_btn.disabled = true
	_gap_labels[_active_gap].text = tile_text
	var next : int = (_active_gap + 1) % _tile_slots.size()
	for _i in range(_tile_slots.size()):
		if _tile_slots[next] == "":
			break
		next = (next + 1) % _tile_slots.size()
	_active_gap = next
	_update_gap_highlight()


func _update_gap_highlight() -> void:
	for i in range(_gap_labels.size()):
		if i == _active_gap:
			_gap_labels[i].add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			_gap_labels[i].remove_theme_color_override("font_color")


func _on_fill_tiles_confirm() -> void:
	if _locked: return
	_locked = true
	var placements : Dictionary = {}
	for i in range(_tile_slots.size()):
		placements[str(i)] = _tile_slots[i]
	var result : Dictionary = QuizManager.answer_current({"placements": placements})
	_finish_complex(result.get("correct", false))


func _on_fill_text_confirm() -> void:
	if _locked: return
	_locked = true
	var input := _answers_box.get_node_or_null("FillTextInput") as LineEdit
	if not input:
		_locked = false
		return
	var result : Dictionary = QuizManager.answer_current({"text": input.text})
	_finish_complex(result.get("correct", false))


func _on_match_left(index: int) -> void:
	_match_selected = index
	for i in range(_match_left_btns.size()):
		if i == index:
			_match_left_btns[i].add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			_match_left_btns[i].remove_theme_color_override("font_color")


func _on_match_right(index: int) -> void:
	if _match_selected < 0:
		return
		
	var left_items : Array = _question.get("left_items", [])

	for key in _match_pairs.keys():
		if _match_pairs[key] == index:
			_match_pairs.erase(key)
			if key < _match_left_btns.size():
				_match_left_btns[key].text = str(left_items[key])

	_match_pairs[_match_selected] = index
	
	if _match_selected < _match_left_btns.size():
		_match_left_btns[_match_selected].text = str(left_items[_match_selected]) + " ✓"
		
	_match_selected = -1
	
	for btn : Button in _match_left_btns:
		btn.remove_theme_color_override("font_color")
		
	for i in range(_match_right_btns.size()):
		if _match_pairs.values().has(i):
			_match_right_btns[i].add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		else:
			_match_right_btns[i].remove_theme_color_override("font_color")


func _on_matching_confirm() -> void:
	if _locked: return
	_locked = true
	var pairs : Array = []
	for left_idx : int in _match_pairs:
		pairs.append({"left_index": left_idx, "right_index": _match_pairs[left_idx]})
	var result : Dictionary = QuizManager.answer_current({"pairs": pairs})
	_finish_complex(result.get("correct", false))


# ─────────────────────────────────────────────────────────────────────────────
# Logika odpowiedzi
# ─────────────────────────────────────────────────────────────────────────────

func _submit_answer(player_id: int, answer_index: int) -> void:
	if _locked: 
		_dbg("Input zablokowany - ignoruję odpowiedź gracza %d" % player_id)
		return
	
	_locked = true
	var qtype : String = _question.get("type", "multiple_choice")
	var is_correct : bool = false

	if qtype == "multiple_choice":
		is_correct = (answer_index == _question.get("correct_index", -1) as int)
	elif qtype == "true_false":
		var bool_val : bool = (answer_index == 0)
		is_correct = (bool_val == _question.get("correct_answer", false) as bool)

	_dbg("Gracz %d odpowiedział (idx: %d). Poprawnie? %s" % [player_id, answer_index, str(is_correct)])

	var btns : Array = _answers_box.get_children()
	if answer_index < btns.size():
		var btn := btns[answer_index] as Button
		if is_correct:
			btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		else:
			btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	if player_id == 1:
		_answered_p1 = true
		_correct_p1 = is_correct
	else:
		_answered_p2 = true
		_correct_p2 = is_correct

	_check_versus_done()

func _show_complex_result(correct: bool) -> void:
	var qtype : String = _question.get("type", "multiple_choice")

	if correct:
		var lbl := Label.new()
		lbl.text = "✅ Poprawnie!"
		lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		_answers_box.add_child(lbl)
		return

	var lbl_wrong := Label.new()
	lbl_wrong.text = "❌ Błędna odpowiedź!"
	lbl_wrong.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_answers_box.add_child(lbl_wrong)

	if qtype == "fill_text":
		var main_answer : String = _question.get("answer", "")
		var alternatives : Array = _question.get("accepted_alternatives", [])
		var all_correct : Array[String] = [main_answer]
		for alt in alternatives:
			all_correct.append(str(alt))
		var lbl := Label.new()
		lbl.text = "Poprawne odpowiedzi: %s" % ", ".join(all_correct)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_answers_box.add_child(lbl)

	elif qtype == "fill_tiles":
			var gaps : Array = _question.get("gaps", [])
			var correct_texts : Array[String] = []
			for g in gaps:
				correct_texts.append(str(g.get("correct", "")))
			var lbl := Label.new()
			lbl.text = "Poprawna kolejność: %s" % ", ".join(correct_texts)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_answers_box.add_child(lbl)
	elif qtype == "matching":
		var left_items : Array = _question.get("left_items", [])
		var right_items : Array = _question.get("right_items", [])
		var pairs : Array = _question.get("pairs", [])
		
		var correct_matches : Array[String] = []
		for pair in pairs:
			var l_idx = pair.get("left_index", -1)
			var r_idx = pair.get("right_index", -1)
			if l_idx >= 0 and l_idx < left_items.size() and r_idx >= 0 and r_idx < right_items.size():
				correct_matches.append(str(left_items[l_idx]) + " ➔ " + str(right_items[r_idx]))
		
		var lbl := Label.new()
		lbl.text = "Poprawne dopasowania:\n" + "\n".join(correct_matches)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_answers_box.add_child(lbl)


func _check_versus_done() -> void:
	match _mode:
		RivalMode.SOLO, RivalMode.DUEL_P1, RivalMode.DUEL_P2:
			var correct : bool = _correct_p2 if _mode == RivalMode.DUEL_P2 else _correct_p1
			_timer_node.stop()
			await get_tree().create_timer(2.0).timeout
			_locked = false
			_route_duel_result(correct)
		RivalMode.VERSUS:
			_timer_node.stop()
			await get_tree().create_timer(3.0).timeout
			_resolve_versus()

func _finish_complex(correct: bool) -> void:
	_timer_node.stop()
	_show_complex_result(correct)
	await get_tree().create_timer(2.0).timeout
	_locked = false
	_route_duel_result(correct)

func _route_duel_result(correct: bool) -> void:
	_dbg("Rozstrzyganie pojedynku. Czy martwy odpowiedział OK? %s" % str(correct))
	
	if _mode == RivalMode.DUEL_P1:
		if correct:
			_dbg("RESULT: P1 OK -> Kod 0 (Kolej P2)")
			_emit_result(0)
		else:
			_dbg("RESULT: P1 BŁĄD -> Kod 2 (P1 odpada)")
			_emit_result(2)
	elif _mode == RivalMode.DUEL_P2:
		if correct:
			_dbg("RESULT: P2 OK -> Kod 3 (Kolej P1)")
			_emit_result(3)
		else:
			_dbg("RESULT: P2 BŁĄD -> Kod 1 (P2 odpada)")
			_emit_result(1)
	else:
		_dbg("RESULT: SOLO/Inny. Sukces? %s" % str(correct))
		_emit_result(1 if correct else 2)

func _resolve_versus() -> void:
	_dbg("Rozstrzyganie VERSUS (Kto pierwszy...)")
	if _answered_p1:
		_dbg("P1 był pierwszy. Poprawnie? %s" % str(_correct_p1))
		_emit_result(1 if _correct_p1 else 2)
	elif _answered_p2:
		_dbg("P2 był pierwszy. Poprawnie? %s" % str(_correct_p2))
		_emit_result(2 if _correct_p2 else 1)
		
func _on_timer_timeout() -> void:
	_dbg("Czas minął!")
	if _mode == RivalMode.VERSUS:
		_dbg("VERSUS Timeout -> Faworyzuję obrońcę")
		_emit_result(2 if current_dead_player == 1 else 1)
	elif _mode == RivalMode.DUEL_P1:
		_emit_result(2)
	elif _mode == RivalMode.DUEL_P2:
		_emit_result(1)
	else:
		_emit_result(2)

func _emit_result(winner_id: int) -> void:
	_dbg("EMIT RESULT: %d" % winner_id)
	visible = false
	quiz_result.emit(winner_id)


# ─────────────────────────────────────────────────────────────────────────────
# Timer display
# ─────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not visible or _timer_node.is_stopped():
		return
	_time_left = _timer_node.time_left
	var pct : float = _time_left / _total_time
	var color : Color = Color(0.3, 1.0, 0.3).lerp(Color(1.0, 0.2, 0.2), 1.0 - pct)
	_lbl_timer.text = "⏱ %.1f s" % _time_left
	_lbl_timer.add_theme_color_override("font_color", color)
