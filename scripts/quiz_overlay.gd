extends CanvasLayer

## Quiz Overlay — wyświetla pytanie quizowe podczas "ostatniej szansy".
##
## Tryby rywalizacji:
##   SOLO       — tylko gracz 1 odpowiada
##   VERSUS     — obaj gracze odpowiadają jednocześnie (multiple_choice / true_false)
##   DUEL_P1    — turniej: teraz odpowiada Gracz 1
##   DUEL_P2    — turniej: teraz odpowiada Gracz 2

signal quiz_result(winner_id: int)

enum RivalMode { SOLO, VERSUS, DUEL_P1, DUEL_P2 }

const WORDS_PER_SEC   : float = 0.35
const DIFF_STEP_SEC   : float = 3.0
const TYPE_MULTIPLIER : Dictionary = {
	"true_false":      0.80,
	"multiple_choice": 1.00,
	"fill_text":       1.20,
	"fill_tiles":      1.40,
	"matching":        1.55,
}

# Bazowe rozmiary czcionek z .tscn
const BASE_FS_TITLE      := 24
const BASE_FS_QUESTION   := 21
const BASE_FS_TIMER      := 20
const BASE_FS_HINT       := 15
const BASE_FS_ANSWER_BTN := 20
const BASE_FS_RESULT     := 22
const BASE_FS_CORRECT    := 18
const BASE_FS_CONFIRM_MATCH := 18

# Bazowe rozmiary panelu i separatorow z .tscn
const BASE_PANEL_HALF_W := 340.0
const BASE_PANEL_HALF_H := 300.0
const BASE_SEP_VBOX     := 10
const BASE_SEP_SUBBOX   := 6

# ---- stałe węzły ----
@onready var _panel        : PanelContainer  = $Panel
@onready var _vbox         : VBoxContainer   = $Panel/VBox
@onready var _lbl_title    : Label           = $Panel/VBox/Title
@onready var _lbl_question : Label           = $Panel/VBox/Question
@onready var _lbl_timer    : Label           = $Panel/VBox/Timer
@onready var _lbl_hint     : Label           = $Panel/VBox/Hint
@onready var _timer_node   : Timer           = $Timer
@onready var _result_label : Label           = $Panel/VBox/ResultLabel
@onready var _correct_lbl  : Label           = $Panel/VBox/CorrectAnswer

# multiple_choice
@onready var _mc_box  : VBoxContainer = $Panel/VBox/MC_Box
@onready var _mc_btns : Array[Button] = [
	$Panel/VBox/MC_Box/Btn0,
	$Panel/VBox/MC_Box/Btn1,
	$Panel/VBox/MC_Box/Btn2,
	$Panel/VBox/MC_Box/Btn3,
]

# true_false
@onready var _tf_box   : VBoxContainer = $Panel/VBox/TF_Box
@onready var _btn_true  : Button        = $Panel/VBox/TF_Box/BtnTrue
@onready var _btn_false : Button        = $Panel/VBox/TF_Box/BtnFalse

# fill_text
@onready var _fill_text_box    : VBoxContainer = $Panel/VBox/FillText_Box
@onready var _fill_pattern_lbl : Label         = $Panel/VBox/FillText_Box/PatternHint
@onready var _fill_input       : LineEdit      = $Panel/VBox/FillText_Box/Input
@onready var _fill_confirm     : Button        = $Panel/VBox/FillText_Box/Confirm

# fill_tiles
@onready var _fill_tiles_box : VBoxContainer  = $Panel/VBox/FillTiles_Box
@onready var _gap_row        : HFlowContainer = $Panel/VBox/FillTiles_Box/GapRow
@onready var _tile_row       : HFlowContainer = $Panel/VBox/FillTiles_Box/TileRow
@onready var _tiles_confirm  : Button         = $Panel/VBox/FillTiles_Box/Confirm

# matching
@onready var _matching_box  : VBoxContainer = $Panel/VBox/Matching_Box
@onready var _match_left    : VBoxContainer = $Panel/VBox/Matching_Box/MatchGrid/LeftCol
@onready var _match_right   : VBoxContainer = $Panel/VBox/Matching_Box/MatchGrid/RightCol
@onready var _match_confirm : Button        = $Panel/VBox/Matching_Box/Confirm

# ---- stan ----
var _question    : Dictionary = {}
var _mode        : RivalMode  = RivalMode.SOLO
var _time_left   : float      = 15.0
var _total_time  : float      = 15.0
var _answered_p1 : bool       = false
var _answered_p2 : bool       = false
var _correct_p1  : bool       = false
var _correct_p2  : bool       = false
var _locked      : bool       = false
var current_dead_player : int = 0

# fill_tiles
var _tile_slots   : Array[String] = []
var _tile_buttons : Array[Button] = []
var _gap_buttons  : Array[Button] = []
var _active_gap   : int           = 0

# matching
var _match_selected   : int        = -1
var _match_pairs      : Dictionary = {}
var _match_left_btns  : Array[Button] = []
var _match_right_btns : Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_timer_node.timeout.connect(_on_timer_timeout)
	_fill_confirm.pressed.connect(_on_fill_text_confirm)
	_fill_input.text_submitted.connect(func(_t): _on_fill_text_confirm())
	_tiles_confirm.pressed.connect(_on_fill_tiles_confirm)
	_match_confirm.pressed.connect(_on_matching_confirm)
	for i in _mc_btns.size():
		var idx := i
		_mc_btns[i].pressed.connect(func(): _on_mc_button(idx))
	_btn_true.pressed.connect(func(): _on_tf_button(true))
	_btn_false.pressed.connect(func(): _on_tf_button(false))
	UIScaleManager.scale_changed.connect(_on_scale_changed)
	_on_scale_changed(UIScaleManager.scale_factor)


# ---------------------------------------------------------------------------
# Skalowanie
# ---------------------------------------------------------------------------

func _on_scale_changed(_s: float) -> void:
	# Panel
	var ph := UIScaleManager.sz(BASE_PANEL_HALF_W)
	var pv := UIScaleManager.sz(BASE_PANEL_HALF_H)
	_panel.offset_left   = -ph ; _panel.offset_top    = -pv
	_panel.offset_right  =  ph ; _panel.offset_bottom =  pv
	# Separation
	_vbox.add_theme_constant_override("separation",           UIScaleManager.px(BASE_SEP_VBOX))
	_mc_box.add_theme_constant_override("separation",         UIScaleManager.px(BASE_SEP_SUBBOX))
	_tf_box.add_theme_constant_override("separation",         UIScaleManager.px(BASE_SEP_SUBBOX))
	_fill_text_box.add_theme_constant_override("separation",  UIScaleManager.px(BASE_SEP_SUBBOX))
	_fill_tiles_box.add_theme_constant_override("separation", UIScaleManager.px(BASE_SEP_SUBBOX))
	_matching_box.add_theme_constant_override("separation",   UIScaleManager.px(BASE_SEP_SUBBOX))
	# Etykiety nagłówkowe
	_lbl_title.add_theme_font_size_override("font_size",    UIScaleManager.px(BASE_FS_TITLE))
	_lbl_question.add_theme_font_size_override("font_size", UIScaleManager.px(BASE_FS_QUESTION))
	_lbl_timer.add_theme_font_size_override("font_size",    UIScaleManager.px(BASE_FS_TIMER))
	_lbl_hint.add_theme_font_size_override("font_size",     UIScaleManager.px(BASE_FS_HINT))
	_result_label.add_theme_font_size_override("font_size", UIScaleManager.px(BASE_FS_RESULT))
	_correct_lbl.add_theme_font_size_override("font_size",  UIScaleManager.px(BASE_FS_CORRECT))
	# Statyczne przyciski odpowiedzi (MC / TF)
	var fs_btn := UIScaleManager.px(BASE_FS_ANSWER_BTN)
	for btn in _mc_btns:
		(btn as Button).add_theme_font_size_override("font_size", fs_btn)
	_btn_true.add_theme_font_size_override("font_size",  fs_btn)
	_btn_false.add_theme_font_size_override("font_size", fs_btn)
	# FillText
	_fill_pattern_lbl.add_theme_font_size_override("font_size", UIScaleManager.px(BASE_FS_ANSWER_BTN))
	_fill_input.add_theme_font_size_override("font_size",       UIScaleManager.px(BASE_FS_ANSWER_BTN))
	_fill_confirm.add_theme_font_size_override("font_size",     UIScaleManager.px(BASE_FS_ANSWER_BTN))
	# FillTiles confirm
	_tiles_confirm.add_theme_font_size_override("font_size", UIScaleManager.px(BASE_FS_ANSWER_BTN))
	# Matching confirm
	_match_confirm.add_theme_font_size_override("font_size", UIScaleManager.px(BASE_FS_CONFIRM_MATCH))


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

static func calculate_time(question: Dictionary, base_time: float, base_difficulty: int) -> float:
	var word_count : int = 0
	for field in [question.get("question",""), question.get("statement",""),
			question.get("prompt",""), question.get("text_with_gaps","")]:
		if field != "": word_count += (field as String).split(" ",false).size()
	for ans in question.get("answers", []): word_count += str(ans).split(" ",false).size()
	for item in question.get("left_items",  []): word_count += str(item).split(" ",false).size()
	for item in question.get("right_items", []): word_count += str(item).split(" ",false).size()
	var word_bonus  : float  = float(word_count) * WORDS_PER_SEC
	var qtype       : String = question.get("type", "multiple_choice")
	var type_mult   : float  = TYPE_MULTIPLIER.get(qtype, 1.0)
	var diff_offset : float  = float(question.get("difficulty", base_difficulty) - base_difficulty) * DIFF_STEP_SEC
	return clampf((base_time + word_bonus) * type_mult + diff_offset, 5.0, 120.0)


func show_quiz(question: Dictionary, rival_mode: RivalMode, time_limit: float, dead_pid: int = 0) -> void:
	_question   = question
	_mode       = rival_mode
	_time_left  = time_limit
	_total_time = time_limit
	current_dead_player = dead_pid
	_dbg("--- START --- Typ: %s" % question.get("type", "unknown"))
	_answered_p1 = false
	_answered_p2 = false
	_correct_p1  = false
	_correct_p2  = false
	_tile_slots.clear()
	_tile_buttons.clear()
	_gap_buttons.clear()
	_active_gap        = 0
	_match_selected    = -1
	_match_pairs.clear()
	_match_left_btns.clear()
	_match_right_btns.clear()
	_result_label.visible  = false
	_correct_lbl.visible   = false
	_build_ui()
	visible = true
	_timer_node.wait_time = time_limit
	_timer_node.start()
	var qtype : String = question.get("type", "multiple_choice")
	_locked = (qtype == "multiple_choice" or qtype == "true_false")
	if _locked:
		get_tree().create_timer(0.5).timeout.connect(func(): _locked = false)


# ---------------------------------------------------------------------------
# Budowanie UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var qtype : String = _question.get("type", "multiple_choice")
	_mc_box.visible         = false
	_tf_box.visible         = false
	_fill_text_box.visible  = false
	_fill_tiles_box.visible = false
	_matching_box.visible   = false

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
			_lbl_hint.text = "P%d: wpisz odpowiedź – Enter aby zatwierdzić" % (2 if _mode == RivalMode.DUEL_P2 else 1)
		"fill_tiles":
			_lbl_hint.text = "Kliknij kafle aby wypełnić lukę | Tab – zmień lukę"
		"matching":
			_lbl_hint.text = "Kliknij element po lewej, potem po prawej | Enter – zatwierdź"

	match qtype:
		"multiple_choice": _build_mc()
		"true_false":       _build_tf()
		"fill_text":        _build_fill_text()
		"fill_tiles":       _build_fill_tiles()
		"matching":         _build_matching()
	_lbl_question.visible = _lbl_question.text != ""


# --- multiple_choice ---
func _build_mc() -> void:
	_mc_box.visible = true
	var answers : Array = _question.get("answers", [])
	var keys_p1 : Array[String] = ["W", "S", "A", "D"]
	var keys_p2 : Array[String] = ["↑", "↓", "←", "→"]
	for i in _mc_btns.size():
		var btn := _mc_btns[i]
		if i < answers.size():
			var txt := str(answers[i])
			if _mode == RivalMode.VERSUS:
				btn.text = "[%s/%s]  %s" % [keys_p1[i], keys_p2[i], txt]
			elif _mode == RivalMode.DUEL_P2:
				btn.text = "[%s]  %s" % [keys_p2[i], txt]
			else:
				btn.text = "[%s]  %s" % [keys_p1[i], txt]
			btn.visible = true
			btn.remove_theme_color_override("font_color")
		else:
			btn.visible = false


# --- true_false ---
func _build_tf() -> void:
	_tf_box.visible = true
	var k1 : Array[String] = ["W", "S"]
	var k2 : Array[String] = ["↑", "↓"]
	var labels := ["Prawda", "Fałsz"]
	var btns   := [_btn_true, _btn_false]
	for i in 2:
		if _mode == RivalMode.VERSUS:
			btns[i].text = "[%s/%s]  %s" % [k1[i], k2[i], labels[i]]
		elif _mode == RivalMode.DUEL_P2:
			btns[i].text = "[%s]  %s" % [k2[i], labels[i]]
		else:
			btns[i].text = "[%s]  %s" % [k1[i], labels[i]]
		btns[i].remove_theme_color_override("font_color")


# --- fill_text ---
func _build_fill_text() -> void:
	_fill_text_box.visible = true
	var pattern : String = _question.get("prefilled_pattern", "")
	_fill_pattern_lbl.text    = "Podpowiedź: %s" % pattern
	_fill_pattern_lbl.visible = pattern != ""
	_fill_input.text = ""
	_fill_input.grab_focus()


# --- fill_tiles ---
func _build_fill_tiles() -> void:
	_fill_tiles_box.visible = true
	for ch in _gap_row.get_children():  ch.queue_free()
	for ch in _tile_row.get_children(): ch.queue_free()
	var text_with_gaps : String = _question.get("text_with_gaps", "")
	var gaps  : Array = _question.get("gaps", [])
	var tiles : Array = _question.get("tiles", [])
	_tile_slots.resize(gaps.size())
	_tile_slots.fill("")
	var fs := UIScaleManager.px(BASE_FS_ANSWER_BTN)
	var parts := text_with_gaps.split("___")
	for i in parts.size():
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", fs)
		lbl.text = parts[i]
		_gap_row.add_child(lbl)
		if i < gaps.size():
			var gap_btn := Button.new()
			gap_btn.add_theme_font_size_override("font_size", fs)
			gap_btn.focus_mode = Control.FOCUS_NONE
			gap_btn.custom_minimum_size = UIScaleManager.sz2(120, 36)
			gap_btn.text = "[ ___ ]"
			var idx := i
			gap_btn.pressed.connect(func(): _on_gap_clicked(idx))
			_gap_row.add_child(gap_btn)
			_gap_buttons.append(gap_btn)
	for tile in tiles:
		var tbtn := Button.new()
		tbtn.add_theme_font_size_override("font_size", fs)
		tbtn.text = str(tile)
		tbtn.focus_mode = Control.FOCUS_NONE
		var txt := str(tile)
		tbtn.pressed.connect(func(): _on_tile_clicked(txt, tbtn))
		_tile_row.add_child(tbtn)
		_tile_buttons.append(tbtn)
	_update_gap_highlight()


# --- matching ---
func _build_matching() -> void:
	_matching_box.visible = true
	for ch in _match_left.get_children():  ch.queue_free()
	for ch in _match_right.get_children(): ch.queue_free()
	var left_items  : Array = _question.get("left_items", [])
	var right_items : Array = _question.get("right_items", [])
	var fs := UIScaleManager.px(BASE_FS_ANSWER_BTN)
	for i in left_items.size():
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", fs)
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = str(left_items[i])
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func(): _on_match_left(idx))
		_match_left.add_child(btn)
		_match_left_btns.append(btn)
	for i in right_items.size():
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", fs)
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = str(right_items[i])
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func(): _on_match_right(idx))
		_match_right.add_child(btn)
		_match_right_btns.append(btn)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
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
	var count : int = (_question.get("answers", []) as Array).size() if qtype == "multiple_choice" else 2
	var p1_keys : Array[Key] = [KEY_W, KEY_S, KEY_A, KEY_D]
	var p2_keys : Array[Key] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	for i in range(min(count, 4)):
		if _mode in [RivalMode.SOLO, RivalMode.VERSUS, RivalMode.DUEL_P1]:
			if ke.keycode == p1_keys[i] and not _answered_p1:
				_submit_answer(1, i); get_viewport().set_input_as_handled(); return
		if _mode in [RivalMode.VERSUS, RivalMode.DUEL_P2]:
			if ke.keycode == p2_keys[i] and not _answered_p2:
				_submit_answer(2, i); get_viewport().set_input_as_handled(); return


# ---------------------------------------------------------------------------
# Handlery przycisków
# ---------------------------------------------------------------------------

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
	if _tile_slots.size() == 0: return
	var old_tile : String = _tile_slots[_active_gap]
	if old_tile != "":
		for tbtn in _tile_buttons:
			if tbtn.text == old_tile:
				tbtn.disabled = false; break
	_tile_slots[_active_gap] = tile_text
	tile_btn.disabled = true
	_gap_buttons[_active_gap].text = tile_text
	var next := (_active_gap + 1) % _tile_slots.size()
	for _i in _tile_slots.size():
		if _tile_slots[next] == "": break
		next = (next + 1) % _tile_slots.size()
	_active_gap = next
	_update_gap_highlight()


func _update_gap_highlight() -> void:
	for i in _gap_buttons.size():
		if i == _active_gap:
			_gap_buttons[i].add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			_gap_buttons[i].remove_theme_color_override("font_color")


func _on_fill_text_confirm() -> void:
	if _locked: return
	_locked = true
	var result : Dictionary = QuizManager.answer_current({"text": _fill_input.text})
	_finish_complex(result.get("correct", false))


func _on_fill_tiles_confirm() -> void:
	if _locked: return
	_locked = true
	var placements : Dictionary = {}
	for i in _tile_slots.size():
		placements[str(i)] = _tile_slots[i]
	var result : Dictionary = QuizManager.answer_current({"placements": placements})
	_finish_complex(result.get("correct", false))


func _on_matching_confirm() -> void:
	if _locked: return
	_locked = true
	var pairs : Array = []
	for left_idx : int in _match_pairs:
		pairs.append({"left_index": left_idx, "right_index": _match_pairs[left_idx]})
	var result : Dictionary = QuizManager.answer_current({"pairs": pairs})
	_finish_complex(result.get("correct", false))


func _on_match_left(index: int) -> void:
	_match_selected = index
	for i in _match_left_btns.size():
		if i == index: _match_left_btns[i].add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else: _match_left_btns[i].remove_theme_color_override("font_color")


func _on_match_right(index: int) -> void:
	if _match_selected < 0: return
	var left_items : Array = _question.get("left_items", [])
	for key in _match_pairs.keys():
		if _match_pairs[key] == index:
			_match_pairs.erase(key)
			if key < _match_left_btns.size():
				_match_left_btns[key].text = str(left_items[key])
				_match_left_btns[key].remove_theme_color_override("font_color")
	_match_pairs[_match_selected] = index
	if _match_selected < _match_left_btns.size():
		_match_left_btns[_match_selected].text = str(left_items[_match_selected]) + " ✓"
	_match_selected = -1
	for btn in _match_left_btns:  btn.remove_theme_color_override("font_color")
	for i in _match_right_btns.size():
		if _match_pairs.values().has(i): _match_right_btns[i].add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		else: _match_right_btns[i].remove_theme_color_override("font_color")


# ---------------------------------------------------------------------------
# Logika odpowiedzi
# ---------------------------------------------------------------------------

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
		is_correct = ((answer_index == 0) == _question.get("correct_answer", false) as bool)
	_dbg("Gracz %d odpowiedział (idx: %d). Poprawnie? %s" % [player_id, answer_index, str(is_correct)])
	var highlight_btns : Array[Button] = _mc_btns if qtype == "multiple_choice" else _tf_btns()
	if answer_index < highlight_btns.size():
		highlight_btns[answer_index].add_theme_color_override("font_color",
			Color(0.3, 1.0, 0.4) if is_correct else Color(1.0, 0.3, 0.3))
	if player_id == 1: _answered_p1 = true; _correct_p1 = is_correct
	else:              _answered_p2 = true; _correct_p2 = is_correct
	_check_versus_done()


func _tf_btns() -> Array[Button]:
	var arr : Array[Button] = []
	arr.append(_btn_true)
	arr.append(_btn_false)
	return arr


func _finish_complex(correct: bool) -> void:
	_timer_node.stop()
	_show_result_label(correct)
	await get_tree().create_timer(2.0).timeout
	_locked = false
	_route_duel_result(correct)


func _show_result_label(correct: bool) -> void:
	var qtype : String = _question.get("type", "multiple_choice")
	_result_label.visible = true
	if correct:
		_result_label.text = "✅ Poprawnie!"
		_result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		_correct_lbl.visible = false
		return
	_result_label.text = "❌ Błędna odpowiedź!"
	_result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	match qtype:
		"fill_text":
			var main_ans : String = _question.get("answer", "")
			var alts : Array = _question.get("accepted_alternatives", [])
			var all_c : Array[String] = [main_ans]
			for a in alts: all_c.append(str(a))
			_correct_lbl.text = "Poprawne: %s" % ", ".join(all_c)
			_correct_lbl.visible = true
		"fill_tiles":
			var gaps : Array = _question.get("gaps", [])
			var correct_txts : Array[String] = []
			for g in gaps: correct_txts.append(str(g.get("correct", "")))
			_correct_lbl.text = "Poprawna kolejność: %s" % ", ".join(correct_txts)
			_correct_lbl.visible = true
		"matching":
			var li : Array = _question.get("left_items", [])
			var ri : Array = _question.get("right_items", [])
			var lines : Array[String] = []
			for pair in _question.get("pairs", []):
				var l : int = pair.get("left_index", -1)
				var r : int = pair.get("right_index", -1)
				if l >= 0 and l < li.size() and r >= 0 and r < ri.size():
					lines.append("%s → %s" % [str(li[l]), str(ri[r])])
			_correct_lbl.text = "Poprawne:\n" + "\n".join(lines)
			_correct_lbl.visible = true
		_:
			_correct_lbl.visible = false


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


func _route_duel_result(correct: bool) -> void:
	_dbg("Rozstrzyganie pojedynku. Czy martwy odpowiedział OK? %s" % str(correct))
	if _mode == RivalMode.DUEL_P1:
		if correct: _dbg("RESULT: P1 OK -> Kod 0 (Kolej P2)");    _emit_result(0)
		else:       _dbg("RESULT: P1 BŁĄD -> Kod 2 (P1 odpada)"); _emit_result(2)
	elif _mode == RivalMode.DUEL_P2:
		if correct: _dbg("RESULT: P2 OK -> Kod 3 (Kolej P1)");    _emit_result(3)
		else:       _dbg("RESULT: P2 BŁĄD -> Kod 1 (P2 odpada)"); _emit_result(1)
	else:
		_emit_result(1 if correct else 2)


func _resolve_versus() -> void:
	_dbg("Rozstrzyganie VERSUS")
	if _answered_p1:   _emit_result(1 if _correct_p1 else 2)
	elif _answered_p2: _emit_result(2 if _correct_p2 else 1)
	else:              _emit_result(2)


func _on_timer_timeout() -> void:
	_dbg("Czas minął!")
	match _mode:
		RivalMode.VERSUS:  _emit_result(2 if current_dead_player == 1 else 1)
		RivalMode.DUEL_P1: _emit_result(2)
		RivalMode.DUEL_P2: _emit_result(1)
		_:                 _emit_result(2)


func _emit_result(winner_id: int) -> void:
	_dbg("EMIT RESULT: %d" % winner_id)
	visible = false
	quiz_result.emit(winner_id)


# ---------------------------------------------------------------------------
# Timer display
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible or _timer_node.is_stopped(): return
	_time_left = _timer_node.time_left
	var pct : float = _time_left / _total_time
	var color := Color(0.3, 1.0, 0.3).lerp(Color(1.0, 0.2, 0.2), 1.0 - pct)
	_lbl_timer.text = "⏱ %.1f s" % _time_left
	_lbl_timer.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

func _dbg(msg: String) -> void:
	if GameManager.debug_enabled:
		print("[QUIZ | %s | Dead:P%d] %s" % [RivalMode.keys()[_mode], current_dead_player, msg])
