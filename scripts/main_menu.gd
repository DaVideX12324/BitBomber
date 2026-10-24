extends CanvasLayer

## Menu główne BitBomber — wygląd w main_menu.tscn (motyw resources/ui/bb_theme.tres), tu tylko logika.

const V := "Root/Center/Panel/VBox/"
const G := V + "Grid/"

@onready var _root     : Control         = $Root
@onready var _ver_label : Label          = $Root/VerLabel
@onready var _rounds_label  : Label        = get_node(G + "RoundsLabel")
@onready var _quiz_opt      : OptionButton = get_node(G + "QuizOpt")
@onready var _map_opt       : OptionButton = get_node(G + "MapOpt")
@onready var _rounds_spin   : SpinBox      = get_node(G + "RoundsSpin")
@onready var _start_btn     : Button       = get_node(V + "BtnStart")
@onready var _help_btn      : Button       = get_node(V + "HBoxMeta/BtnHelp")
@onready var _options_btn   : Button       = get_node(V + "HBoxMeta/BtnOptions")
@onready var _quit_btn      : Button       = get_node(V + "HBoxMeta/BtnQuit")
@onready var _local_options_menu: CanvasLayer = $OptionsMenu
@onready var _help_overlay  : Control       = $Root/HelpOverlay
@onready var _help_body     : RichTextLabel = $Root/HelpOverlay/HelpPanel/VBox/Scroll/HelpBody
@onready var _help_close    : Button        = $Root/HelpOverlay/HelpPanel/VBox/HelpClose

@onready var _players_btns : Array[Button] = [get_node(G + "HBoxPlayers/Players_1"), get_node(G + "HBoxPlayers/Players_2")]
@onready var _bots_btns : Array[Button] = [
	get_node(G + "HBoxBots/Bots_0"), get_node(G + "HBoxBots/Bots_1"),
	get_node(G + "HBoxBots/Bots_2"), get_node(G + "HBoxBots/Bots_3"),
]
@onready var _diff_btns : Array[Button] = [
	get_node(G + "HBoxDiff/Diff_Easy"), get_node(G + "HBoxDiff/Diff_Medium"), get_node(G + "HBoxDiff/Diff_Hard"),
]
@onready var _mode_btns : Array[Button] = [get_node(G + "HBoxMode/Mode_Last"), get_node(G + "HBoxMode/Mode_Kill")]
@onready var _win_btns : Array[Button] = [get_node(G + "HBoxWin/Win_FirstTo"), get_node(G + "HBoxWin/Win_MostWins")]

## Rozmiary z .tscn (minimalny rozmiar, czcionka) zapamiętane przy starcie — UIScaleManager je przelicza.
var _base_sizes : Dictionary = {}

var _sel_players : int = 1
var _sel_bots    : int = 1
var _sel_diff    : int = 0
var _sel_win     : int = 0
var _sel_mode    : int = 0

var _options_menu: CanvasLayer

const HOST_OPTIONS_MENU_SCENE := "res://scenes/ui/options_menu.tscn"
const Arena = preload("arena.gd")
const BbMusic = preload("bb_music.gd")
const BBRuntime = preload("bb_runtime.gd")

## Wersja z module_manifest.json do wyświetlenia: "0.9.0-beta" -> "0.9.0 Beta" (zasady wersjonowania: docs hosta).
func _version_label() -> String:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(BBRuntime.path("module_manifest.json")))
	var version := str(manifest.get("version", "")) if manifest is Dictionary else ""
	var parts := version.split("-", true, 1)
	if parts.size() < 2:
		return version
	var stage := parts[1]
	stage = "RC" + stage.substr(2) if stage.begins_with("rc") else stage.left(1).to_upper() + stage.substr(1)
	return "%s %s" % [parts[0], stage]


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
	BbMusic.play("menu")
	_ver_label.text = "BitBomber " + _version_label()
	_options_menu = _resolve_options_menu()
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
	for i in _mode_btns.size():
		var idx := i
		_mode_btns[i].pressed.connect(func(): _set_mode(idx))
	var gm0 := _gm()
	if gm0 and gm0.get("game_mode") != null:
		_sel_mode = int(gm0.game_mode)
	_rounds_spin.value_changed.connect(_on_rounds_changed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	_help_btn.pressed.connect(_show_help)
	_options_btn.pressed.connect(func(): _options_menu.open())
	var qm := _qm()
	var quizzes: Array = qm.get_quiz_ids() if qm else []
	_quiz_opt.add_item(BbI18n.t("bb.menu.quiz_all", "Wszystkie"))
	for q in quizzes:
		_quiz_opt.add_item(q)
	_fill_maps()
	_start_btn.pressed.connect(func():
		var q_id = "" if _quiz_opt.selected <= 0 \
				else _quiz_opt.get_item_text(_quiz_opt.selected)
		_start(_sel_players, _sel_bots, _sel_diff, _sel_win,
				int(_rounds_spin.value), q_id)
	)
	_refresh_players()
	_refresh_bots()
	_refresh_diff()
	_refresh_win()
	_refresh_mode()
	_help_body.text = BbI18n.t("bb.help.body")
	_help_close.pressed.connect(_hide_help)
	_update_quit_button()
	_collect_base_sizes(_root)
	var sm := get_node_or_null("/root/UIScaleManager")
	if sm and sm.has_signal("scale_changed"):
		sm.scale_changed.connect(_on_scale_changed)
		_on_scale_changed(float(sm.get("scale_factor")))


func _resolve_options_menu() -> CanvasLayer:
	var host_settings := get_node_or_null("/root/SettingsService")
	if host_settings and ResourceLoader.exists(HOST_OPTIONS_MENU_SCENE):
		var host_scene := load(HOST_OPTIONS_MENU_SCENE) as PackedScene
		if host_scene:
			var host_menu := host_scene.instantiate() as CanvasLayer
			if host_menu:
				_local_options_menu.queue_free()
				add_child(host_menu)
				return host_menu
	return _local_options_menu


# ---------------------------------------------------------------------------
# Skalowanie
# ---------------------------------------------------------------------------

func _on_scale_changed(_s: float) -> void:
	for c: Control in _base_sizes:
		var base: Array = _base_sizes[c]
		c.custom_minimum_size = _sz2(base[0].x, base[0].y)
		c.add_theme_font_size_override(_font_key(c), _px(base[1]))
	_scale_popup_font(_map_opt, _px(19))
	_scale_popup_font(_quiz_opt, _px(19))
	var spin_edit := _rounds_spin.get_line_edit()
	if spin_edit:
		spin_edit.add_theme_font_size_override("font_size", _px(19))


func _collect_base_sizes(n: Node) -> void:
	for c in n.get_children():
		if c is Control and c != _rounds_spin.get_line_edit():
			_base_sizes[c] = [c.custom_minimum_size, c.get_theme_font_size(_font_key(c))]
		if not c is OptionButton and not c is SpinBox:
			_collect_base_sizes(c)


func _font_key(c: Control) -> String:
	return "normal_font_size" if c is RichTextLabel else "font_size"


func _scale_popup_font(opt: OptionButton, font_size: int) -> void:
	opt.get_popup().add_theme_font_size_override("font_size", font_size)


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


func _set_mode(idx: int) -> void:
	_sel_mode = idx
	_refresh_mode()


func _refresh_mode() -> void:
	for i in _mode_btns.size():
		_mode_btns[i].button_pressed = (i == _sel_mode)


func _on_rounds_changed(_value: float) -> void:
	if _sel_win == 0:
		_rounds_label.text = BbI18n.t("bb.menu.rounds_to_win_x", "Rundy do wygranej")
	else:
		_rounds_label.text = BbI18n.t("bb.menu.rounds_in_session_y", "Liczba rund")


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
		_rounds_label.text = BbI18n.t("bb.menu.rounds_to_win_x", "Rundy do wygranej")
	else:
		_rounds_label.text = BbI18n.t("bb.menu.rounds_in_session_y", "Liczba rund")


func _start(humans: int, bots: int, diff: int, win_mode: int,
		rounds: int, quiz_id: String) -> void:
	var gm := _gm()
	if gm:
		gm.bot_difficulty   = diff
		gm.game_mode        = _sel_mode
		# Bomb It: skrzynki 0,6–0,8 w arcade, 0,5 w kill (więcej miejsca na walkę)
		gm.box_density      = 0.5 if _sel_mode == gm.GameMode.KILL else 0.7
		gm.win_condition    = win_mode
		gm.selected_quiz_id = quiz_id
		gm.selected_map     = str(_map_opt.get_item_metadata(_map_opt.selected))
		if win_mode == 0:
			gm.rounds_to_win = rounds
		else:
			gm.max_rounds = rounds
		gm.start_game(humans, bots)


## „Losowa” + mapy z resources/maps, np. „Las 2” (wariant 0 = bez numeru). Zaznacza ostatnio wybraną.
func _fill_maps() -> void:
	_map_opt.add_item(BbI18n.t("bb.menu.map_random", "🎲 Losowa"))
	_map_opt.set_item_metadata(0, "")
	var gm := _gm()
	var current : String = gm.selected_map if gm and gm.get("selected_map") != null else ""
	for id in Arena.list_maps():
		var data := Arena.load_map_data(id)
		var name_key := str(data.get("name_key", ""))
		var label := BbI18n.t(name_key, id) if name_key != "" else id
		var variant := int(data.get("variant", 0))
		if variant > 0:
			label += " %d" % variant
		_map_opt.add_item(label)
		_map_opt.set_item_metadata(_map_opt.item_count - 1, id)
		if id == current:
			_map_opt.select(_map_opt.item_count - 1)


func _on_quit_pressed() -> void:
	var gm := _gm()
	if gm and gm.has_method("exit_game"):
		gm.exit_game()
	else:
		get_tree().quit()


func _update_quit_button() -> void:
	var gm := _gm()
	if gm and gm.has_method("is_embedded") and gm.is_embedded():
		_quit_btn.text = BbI18n.t("bb.menu.btn_back_to_host", "✕ Powrót")
	else:
		_quit_btn.text = BbI18n.t("bb.menu.btn_quit", "✕ Wyjście")


# ---------------------------------------------------------------------------
# Instrukcja
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _help_overlay and _help_overlay.visible:
		_hide_help()
		get_viewport().set_input_as_handled()


func _show_help() -> void: _help_overlay.visible = true
func _hide_help() -> void: _help_overlay.visible = false
