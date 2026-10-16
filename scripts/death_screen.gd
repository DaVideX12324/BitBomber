extends CanvasLayer

## Death / Round-end / Game-over overlay.
##
## Tryby działania:
##   LAST_CHANCE  — gracz zginął, quiz daje szansę na respawn
##   ROUND_END    — runda skończyła się
##   GAME_OVER    — cała sesja zakończona

enum Mode { LAST_CHANCE, ROUND_END, GAME_OVER }

@onready var _overlay     : ColorRect      = $Overlay
@onready var _panel       : PanelContainer = $Panel
@onready var _vbox        : VBoxContainer  = $Panel/VBox
@onready var _icon        : Label          = $Panel/VBox/Icon
@onready var _title       : Label          = $Panel/VBox/Title
@onready var _subtitle    : Label          = $Panel/VBox/Subtitle
@onready var _score_table : VBoxContainer  = $Panel/VBox/ScoreTable
@onready var _score_rows  : Array[Label]   = [
	$Panel/VBox/ScoreTable/ScoreRow0,
	$Panel/VBox/ScoreTable/ScoreRow1,
	$Panel/VBox/ScoreTable/ScoreRow2,
	$Panel/VBox/ScoreTable/ScoreRow3,
]
@onready var _btn_cont    : Button         = $Panel/VBox/BtnContinue
@onready var _btn_menu    : Button         = $Panel/VBox/BtnMenu
@onready var _quiz_overlay : CanvasLayer   = $QuizOverlay

# Bazowe rozmiary z .tscn
const BASE_PANEL_HALF_W := 300.0
const BASE_PANEL_HALF_H := 240.0
const BASE_BTN_SIZE     := Vector2(160.0, 44.0)
const BASE_SEP_VBOX     := 16
const BASE_SEP_SCORE    := 4

var _mode           : Mode = Mode.ROUND_END
var _dead_player_id : int  = -1
var _duel_allowed_types : Array[String] = []
var _duel_active    : bool = false
var _duel_p1_score  : int  = 0


func _rm() -> Node:
	return get_node_or_null("/root/RoundManager")


func _gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _qm() -> Node:
	return get_node_or_null("/root/QuizManager")


func _px(val: float) -> int:
	var sm := get_node_or_null("/root/UIScaleManager")
	return int(sm.call("px", val)) if sm and sm.has_method("px") else roundi(val)


func _sz(val: float) -> float:
	var sm := get_node_or_null("/root/UIScaleManager")
	return float(sm.call("sz", val)) if sm and sm.has_method("sz") else val


func _sz2(w: float, h: float) -> Vector2:
	var sm := get_node_or_null("/root/UIScaleManager")
	return sm.call("sz2", w, h) if sm and sm.has_method("sz2") else Vector2(w, h)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_btn_cont.pressed.connect(_on_continue)
	_btn_menu.pressed.connect(_on_menu)
	var rm := _rm()
	if rm:
		rm.last_chance_triggered.connect(_on_last_chance)
		rm.round_ended.connect(_on_round_ended)
		rm.session_ended.connect(_on_session_ended)
	_quiz_overlay.quiz_result.connect(_on_quiz_result)
	_quiz_overlay.visible = false
	var sm := get_node_or_null("/root/UIScaleManager")
	if sm and sm.has_signal("scale_changed"):
		sm.scale_changed.connect(_on_scale_changed)
		_on_scale_changed(float(sm.get("scale_factor")))


func _on_scale_changed(_s: float) -> void:
	# Panel
	var ph := _sz(BASE_PANEL_HALF_W)
	var pv := _sz(BASE_PANEL_HALF_H)
	_panel.offset_left   = -ph ; _panel.offset_top    = -pv
	_panel.offset_right  =  ph ; _panel.offset_bottom =  pv
	# Separation
	_vbox.add_theme_constant_override("separation",        _px(BASE_SEP_VBOX))
	_score_table.add_theme_constant_override("separation", _px(BASE_SEP_SCORE))
	# Czcionki
	_icon.add_theme_font_size_override("font_size",     _px(52))
	_title.add_theme_font_size_override("font_size",    _px(32))
	_subtitle.add_theme_font_size_override("font_size", _px(16))
	var fs_row := _px(20)
	for row in _score_rows:
		(row as Label).add_theme_font_size_override("font_size", fs_row)
	# Przyciski
	var btn_size := _sz2(BASE_BTN_SIZE.x, BASE_BTN_SIZE.y)
	var fs_btn   := _px(21)
	_btn_cont.custom_minimum_size = btn_size
	_btn_cont.add_theme_font_size_override("font_size", fs_btn)
	_btn_menu.custom_minimum_size = btn_size
	_btn_menu.add_theme_font_size_override("font_size", fs_btn)


# ---------------------------------------------------------------------------
# Sygnały z RoundManagera
# ---------------------------------------------------------------------------

func _on_last_chance(dead_player_id: int) -> void:
	_dead_player_id = dead_player_id
	_start_quiz_flow(dead_player_id)


func _on_round_ended(winner_id: int) -> void:
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
	var gm := _gm()
	var diff: int = gm.bot_difficulty if gm else 0
	match diff:
		0: return 20.0
		2: return 10.0
		_: return 15.0


func _get_diff_range() -> Vector2i:
	var gm := _gm()
	var diff: int = gm.bot_difficulty if gm else 0
	match diff:
		0: return Vector2i(1, 3)
		2: return Vector2i(3, 5)
		_: return Vector2i(2, 4)


func _is_quizless_mode_enabled() -> bool:
	var host_settings: Node = get_node_or_null("/root/SettingsService")
	if host_settings and host_settings.has_method("is_quizless_mode_enabled"):
		return bool(host_settings.call("is_quizless_mode_enabled"))

	for key_name: String in ["quizless_mode", "disable_quizzes", "skip_quizzes"]:
		var value: Variant = null
		if host_settings:
			if host_settings.has_method("get_global"):
				value = host_settings.call("get_global", key_name, null)
			elif host_settings.has_method("get_module"):
				value = host_settings.call("get_module", "bitbomber", key_name, null)
			if value != null:
				return bool(value)

		var local_settings: Node = get_node_or_null("/root/SettingsManager")
		if local_settings:
			if local_settings.has_method("get_global"):
				value = local_settings.call("get_global", key_name, null)
			else:
				value = local_settings.get(key_name)
			if value != null:
				return bool(value)

	return false


func _auto_pass_last_chance() -> void:
	_duel_active = false
	_do_resume()
	var rm := _rm()
	if rm:
		rm.resolve_last_chance(true)


func _get_weighted_question(allowed_types: Array = []) -> Dictionary:
	var range_v : Vector2i = _get_diff_range()
	var weights : Array[int]
	var gm := _gm()
	var qm := _qm()
	var diff: int = gm.bot_difficulty if gm else 0
	match diff:
		0: weights = [2, 3, 1]
		2: weights = [2, 3, 1]
		_: weights = [2, 3, 1]
	var all_ids : Array = []
	var sel_id: String = gm.selected_quiz_id if gm else ""
	if sel_id == "" or sel_id == "Wszystkie":
		all_ids = qm.get_quiz_ids() if qm else []
	else:
		all_ids = [sel_id]
	if all_ids.is_empty(): return {}
	var valid_questions : Array = []
	var diffs_available : Array[int] = []
	for quiz_id in all_ids:
		var q_list: Array = qm.get_questions(quiz_id, range_v, 999, allowed_types) if qm else []
		for q in q_list:
			if not allowed_types.is_empty():
				var t = q.get("type", "multiple_choice")
				if not t in allowed_types: continue
			valid_questions.append(q)
			var d : int = q.get("difficulty", 1)
			if not d in diffs_available: diffs_available.append(d)
	if valid_questions.is_empty(): return {}
	diffs_available.sort()
	var max_available_diff = diffs_available.back()
	if max_available_diff < range_v.x:
		range_v.y = max_available_diff
		range_v.x = maxi(1, max_available_diff - (weights.size() - 1))
	var pool : Array = []
	for q in valid_questions:
		var d : int = q.get("difficulty", 1)
		if d >= range_v.x and d <= range_v.y:
			var w_idx := d - range_v.x
			var w : int = weights[w_idx] if w_idx < weights.size() else 1
			for _i in range(w): pool.append(q)
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
	if _is_quizless_mode_enabled():
		_auto_pass_last_chance()
		return
	_do_pause()
	var q := _get_weighted_question([])
	if q.is_empty():
		_auto_pass_last_chance()
		return
	var gm := _gm()
	var qm := _qm()
	var two_player: bool = (gm.num_human_players >= 2) if gm else false
	var simple     := _is_simple_type(q)
	if simple: _duel_allowed_types = ["multiple_choice", "true_false"]
	else:      _duel_allowed_types = ["fill_tiles", "fill_text", "matching"]
	if qm:
		qm.start_custom_questions([q], "last_chance")
	var mode = _quiz_overlay.RivalMode.SOLO
	if two_player:
		if simple:
			mode = _quiz_overlay.RivalMode.VERSUS
		else:
			mode = _quiz_overlay.RivalMode.DUEL_P2 if dead_player_id == 2 else _quiz_overlay.RivalMode.DUEL_P1
	_quiz_overlay.show_quiz(q, mode, _get_time_limit(), dead_player_id)


func _ask_question_p1() -> void:
	var q := _get_weighted_question(_duel_allowed_types)
	if q.is_empty(): _on_quiz_result(1); return
	var qm := _qm()
	if qm:
		qm.start_custom_questions([q], "last_chance")
	_quiz_overlay.show_quiz(q, _quiz_overlay.RivalMode.DUEL_P1, _get_time_limit(), _dead_player_id)


func _ask_question_p2() -> void:
	var q := _get_weighted_question(_duel_allowed_types)
	if q.is_empty(): _on_quiz_result(1); return
	var qm := _qm()
	if qm:
		qm.start_custom_questions([q], "last_chance")
	_quiz_overlay.show_quiz(q, _quiz_overlay.RivalMode.DUEL_P2, _get_time_limit(), _dead_player_id)


# ---------------------------------------------------------------------------
# Wynik quizu
# ---------------------------------------------------------------------------

func _on_quiz_result(winner_id: int) -> void:
	var rm := _rm()
	match [_dead_player_id, winner_id]:
		[1, 1]: _duel_active = false; _do_resume(); if rm: rm.resolve_last_chance(true)
		[1, 2]: _duel_active = false; _do_resume(); if rm: rm.resolve_last_chance(false)
		[2, 2]: _duel_active = false; _do_resume(); if rm: rm.resolve_last_chance(true)
		[2, 1]: _duel_active = false; _do_resume(); if rm: rm.resolve_last_chance(false)
		[1, 0]: _duel_active = true;  _ask_question_p2()
		[2, 3]: _duel_active = true;  _ask_question_p1()
		[1, 3], [2, 0]: _start_quiz_flow(_dead_player_id)


# ---------------------------------------------------------------------------
# Show helpers
# ---------------------------------------------------------------------------

func show_round_end(winner_id: int) -> void:
	_mode = Mode.ROUND_END
	_icon.text = "🏁"
	var cur_round: int = _rm().current_round if _rm() else 1
	if winner_id == 999:
		_title.text = BbI18n.tf("bb.death.bots_won_round", {"round": cur_round})
	else:
		_title.text = BbI18n.tf("bb.death.player_won_round", {"player": winner_id, "round": cur_round})
	_subtitle.text = ""
	_fill_score_table()
	_btn_cont.text = _next_round_label()
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()
	_do_pause()


func show_round_end_draw() -> void:
	_mode = Mode.ROUND_END
	_icon.text = "⏳"
	var cur_round: int = _rm().current_round if _rm() else 1
	_title.text = BbI18n.tf("bb.death.round_draw", {"round": cur_round})
	_subtitle.text = ""
	_fill_score_table()
	_btn_cont.text = _next_round_label()
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()
	_do_pause()


func show_game_over(winner_id: int) -> void:
	_mode = Mode.GAME_OVER
	if winner_id == -1:
		_icon.text = "🤝"
		_title.text = BbI18n.t("bb.death.game_over_draw_title", "Remis!")
		_subtitle.text = BbI18n.t("bb.death.game_over_draw_subtitle", "Obaj gracze zginęli jednocześnie.")
	elif winner_id == 999:
		_icon.text = "🤖"
		_title.text = BbI18n.t("bb.death.game_over_bots_won_title", "Wygrały boty!")
		_subtitle.text = BbI18n.t("bb.death.game_over_bots_won_subtitle", "Lepiej następnym razem.")
	else:
		_icon.text = "🏆"
		_title.text = BbI18n.tf("bb.death.game_over_player_won_title", {"player": winner_id})
		_subtitle.text = ""
	_fill_score_table()
	_btn_cont.visible = false
	_btn_menu.visible = true
	_btn_menu.text = BbI18n.t("bb.death.btn_menu", "Menu główne")
	_show()
	_do_pause()


func _fill_score_table() -> void:
	var lines : Array[String] = []
	var gm := _gm()
	var rm := _rm()
	var n_humans: int = gm.num_human_players if gm else 1
	var n_bots: int = gm.num_bots if gm else 0
	for pid in range(1, n_humans + 1):
		var p_wins: int = rm.get_wins(pid) if rm else 0
		lines.append(BbI18n.plural("bb.death.player_score_row", p_wins, {"player": pid, "n": p_wins}))
	if n_bots > 0:
		var bot_wins: int = rm.get_wins(999) if rm else 0
		for b in range(n_bots):
			if rm:
				bot_wins += rm.get_wins(n_humans + b + 1)
		lines.append(BbI18n.plural("bb.death.bots_score_row", bot_wins, {"n": bot_wins}))
	for i in _score_rows.size():
		if i < lines.size():
			_score_rows[i].text    = lines[i]
			_score_rows[i].visible = true
		else:
			_score_rows[i].visible = false


# ---------------------------------------------------------------------------
# Pauza / wznowienie
# ---------------------------------------------------------------------------

func _do_pause()  -> void: get_tree().paused = true
func _do_resume() -> void: get_tree().paused = false


# ---------------------------------------------------------------------------
# Przyciski
# ---------------------------------------------------------------------------

func _on_continue() -> void:
	match _mode:
		Mode.ROUND_END:
			_do_resume()
			_hide()
			var gm := _gm()
			if gm:
				gm.change_state(1) # GameState.PLAYING
				if gm.game_node:
					gm.game_node.next_round()
		Mode.GAME_OVER:
			pass


func _on_menu() -> void:
	_do_resume()
	_hide()
	var gm := _gm()
	if gm:
		gm.go_to_menu()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _next_round_label() -> String:
	var rm := _rm()
	var gm := _gm()
	var rem: int = rm.rounds_remaining() if rm else 0
	var win_cond = gm.win_condition if gm else 0
	match win_cond:
		0:
			return BbI18n.tf("bb.death.next_round_leader_needs", {"rem": rem})
		1:
			return BbI18n.plural("bb.death.next_round_remaining", rem, {"rem": rem, "n": rem}) if rem > 0 else BbI18n.t("bb.death.last_round", "Ostatnia runda!")
		_:
			return BbI18n.t("bb.death.next_round", "Następna runda")


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
	_btn_cont.visible = true
	_btn_menu.visible = true
