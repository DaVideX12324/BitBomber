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


# ─────────────────────────────────────────────────────────────────────────────
# Publiczne API
# ─────────────────────────────────────────────────────────────────────────────

func show_quiz(question: Dictionary, rival_mode: RivalMode, time_limit: float) -> void:
	_question    = question
	_mode        = rival_mode
	_time_left   = time_limit
	_total_time  = time_limit
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
	_locked=false

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

	var hbox_text := HBoxContainer.new()
	hbox_text.add_theme_constant_override("separation", 4)
	_answers_box.add_child(hbox_text)

	var parts : PackedStringArray = text_with_gaps.split("___")
	for i in range(parts.size()):
		var lbl := Label.new()
		lbl.text = parts[i]
		hbox_text.add_child(lbl)
		if i < gaps.size():
			var gap_btn := Button.new()
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
		tbtn.pressed.connect(_on_tile_clicked.bind(str(tile), tbtn))
		tile_box.add_child(tbtn)
		_tile_buttons.append(tbtn)

	var confirm := Button.new()
	confirm.text = "✔ Zatwierdź (Enter)"
	confirm.pressed.connect(_on_fill_tiles_confirm)
	_answers_box.add_child(confirm)

	_update_gap_highlight()


func _build_fill_text() -> void:
	var pattern : String = _question.get("prefilled_pattern", "")
	if pattern != "":
		var hint_lbl := Label.new()
		hint_lbl.text = "Podpowiedź: %s" % pattern
		hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		_answers_box.add_child(hint_lbl)

	var line_edit := LineEdit.new()
	line_edit.name = "FillTextInput"
	line_edit.placeholder_text = "Wpisz odpowiedź…"
	_answers_box.add_child(line_edit)
	line_edit.grab_focus()

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
	_answers_box.add_child(grid)

	var left_col := VBoxContainer.new()
	grid.add_child(left_col)
	for i in range(left_items.size()):
		var btn := Button.new()
		btn.text = str(left_items[i])
		btn.pressed.connect(_on_match_left.bind(i))
		left_col.add_child(btn)
		_match_left_btns.append(btn)

	var right_col := VBoxContainer.new()
	grid.add_child(right_col)
	for i in range(right_items.size()):
		var btn := Button.new()
		btn.text = str(right_items[i])
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
		if event is InputEventKey and event.pressed:
			var ke := event as InputEventKey
			if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				_on_fill_text_confirm()
				get_viewport().set_input_as_handled()
	elif qtype == "matching":
		if event is InputEventKey and event.pressed:
			var ke := event as InputEventKey
			if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				_on_matching_confirm()
				get_viewport().set_input_as_handled()


func _handle_key_choice(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
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
	var placements : Dictionary = {}
	for i in range(_tile_slots.size()):
		placements[str(i)] = _tile_slots[i]
	var result : Dictionary = QuizManager.answer_current({"placements": placements})
	_finish_complex(result.get("correct", false))


func _on_fill_text_confirm() -> void:
	var input := _answers_box.get_node_or_null("FillTextInput") as LineEdit
	if not input:
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
	_match_pairs[_match_selected] = index
	_match_right_btns[index].add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	var left_items : Array = _question.get("left_items", [])
	if _match_selected < _match_left_btns.size():
		_match_left_btns[_match_selected].text = str(left_items[_match_selected]) + " ✓"
	_match_selected = -1
	for btn : Button in _match_left_btns:
		btn.remove_theme_color_override("font_color")


func _on_matching_confirm() -> void:
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
		return
	_locked = true
	var qtype    : String = _question.get("type", "multiple_choice")
	var is_correct : bool = false

	if qtype == "multiple_choice":
		is_correct = (answer_index == _question.get("correct_index", -1) as int)
	elif qtype == "true_false":
		var bool_val : bool = (answer_index == 0)
		is_correct = (bool_val == _question.get("correct_answer", false) as bool)

	var btns : Array = _answers_box.get_children()
	if answer_index < btns.size():
		var btn := btns[answer_index] as Button
		if is_correct:
			btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		else:
			btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	if player_id == 1:
		_answered_p1 = true
		_correct_p1  = is_correct
	else:
		_answered_p2 = true
		_correct_p2  = is_correct

	_check_versus_done()


func _check_versus_done() -> void:
	match _mode:
		RivalMode.SOLO, RivalMode.DUEL_P1, RivalMode.DUEL_P2:
			var correct : bool = _correct_p2 if _mode == RivalMode.DUEL_P2 else _correct_p1
			_timer_node.stop()
			await get_tree().create_timer(3.0).timeout
			_resolve(correct)
		RivalMode.VERSUS:
			# Pierwszy który odpowie kończy rundę — drugi nie może już odpowiadać
			_timer_node.stop()
			await get_tree().create_timer(3.0).timeout
			_resolve_versus()


func _finish_complex(correct: bool) -> void:
	_timer_node.stop()
	await get_tree().create_timer(0.8).timeout
	_resolve(correct)


func _resolve(p1_correct: bool) -> void:
	if _mode == RivalMode.DUEL_P2:
		if p1_correct:
			_emit_result(0)   # P2 poprawnie → turniej trwa
		else:
			_emit_result(1)   # P2 źle → P1 wygrywa
	else:
		if p1_correct:
			_emit_result(1)   # P1 respawn
		else:
			_emit_result(2)   # P1 odpada


func _resolve_versus() -> void:
	if _correct_p1 and not _correct_p2:
		_emit_result(1)
	elif _correct_p2 and not _correct_p1:
		_emit_result(2)
	elif _correct_p1 and _correct_p2:
		_emit_result(1)   # Obaj poprawnie → P1 respawn
	else:
		_emit_result(2)   # Obaj źle → P1 odpada


func _on_timer_timeout() -> void:
	_emit_result(2)


func _emit_result(winner_id: int) -> void:
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
