extends CanvasLayer

## HUD — UI zdefiniowane w hud.tscn, skrypt tylko wypełnia dane.
##
## Publiczne API:
##   hud.setup_players(player_list: Array)
##   hud.update_lives(pid, lives_left)
##   hud.update_player(pid, bombs, bomb_range, speed_mult, kick, shield)
##   hud.show_message(text, duration)
##   hud.get_quiz_panel(pid)  — panel pytania w trakcie gry (field_quiz.gd)

const PlayerScript = preload("player.gd")
const BBRuntime = preload("bb_runtime.gd")
const ICON_FALLBACK : Dictionary = {
	"bomb_up": "💣", "range_up": "↔️", "speed_up": "⚡", "kick": "🦶", "shield": "🛡",
}

const PLAYER_COLORS: Array[Color] = [
	Color("#3b82f6"),
	Color("#ef4444"),
	Color("#22c55e"),
	Color("#a855f7"),
]

## Pasek czasu: poniżej tylu sekund zegar robi się pomarańczowy
const TIMER_WARN_SECONDS : float = 30.0
const COLOR_TIMER        := Color(1, 0.84, 0.25)
const COLOR_TIMER_WARN   := Color(1, 0.55, 0.15)
const COLOR_TIMER_DANGER := Color(1, 0.3, 0.3)
## Gwiazdki wygranych rund pokazujemy do tylu, dalej „★ 3/10”
const MAX_STARS : int = 7

# Bazy z hud.tscn
const BASE_CARDS_WIDTH  := 300.0
const BASE_CARDS_MARGIN := 16.0  # odstęp kart od lewej krawędzi
const BASE_CARDS_HALF_H := 413.0 # offset_top = -413, offset_bottom = 413
const BASE_TOAST_HALF_W := 240.0 # offset_left = -240, offset_right = 240
const BASE_TOAST_HALF_H := 40.0  # offset_top  =  -40, offset_bottom =  40

@onready var _cards_nodes: Array[Control] = [
	$Root/Cards/Card1,
	$Root/Cards/Card2,
	$Root/Cards/Card3,
	$Root/Cards/Card4,
]
@onready var _cards_box   : VBoxContainer  = $Root/Cards
@onready var _round_panel : PanelContainer = $Root/Cards/RoundPanel
@onready var _round_label : Label          = $Root/Cards/RoundPanel/VBox/RoundLabel
@onready var _timer_label : Label          = $Root/Cards/RoundPanel/VBox/TimerLabel
@onready var _goal_label  : Label          = $Root/Cards/RoundPanel/VBox/GoalLabel
@onready var _toast       : Label          = $Root/ToastLabel
## Panele pytań w trakcie gry (tylko ludzie: gracz 1 i 2)
@onready var _quiz_panels : Array[Control] = [$Root/QuizPanels/QuizPanelP1, $Root/QuizPanels/QuizPanelP2]

## Rozmiary z .tscn (minimalny rozmiar, czcionka) zapamiętane przy starcie — UIScaleManager je przelicza.
var _base_sizes : Dictionary = {}

var _lives : Dictionary = {}   # pid → życia (do odświeżania karty)
var _overtime_shown : bool = false


func _ready() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("state_changed"):
		gm.state_changed.connect(_on_state_changed)
	var rm := get_node_or_null("/root/RoundManager")
	if rm:
		rm.kills_changed.connect(_on_kills_changed)
		rm.round_started.connect(_on_round_started)
		rm.round_ended.connect(func(_w: int) -> void: _refresh_cards())
	for card: Control in _cards_nodes:
		card.visible = false
	_round_panel.visible = false
	visible = false
	_collect_base_sizes(_cards_box)
	_base_sizes[_toast] = [_toast.custom_minimum_size, _toast.get_theme_font_size("font_size")]
	var sm := get_node_or_null("/root/UIScaleManager")
	if sm and sm.has_signal("scale_changed"):
		sm.scale_changed.connect(_on_scale_changed)
		_on_scale_changed(float(sm.get("scale_factor")))


# ---------------------------------------------------------------------------
# Skalowanie
# ---------------------------------------------------------------------------

func _px(val: float) -> int:
	var sm := get_node_or_null("/root/UIScaleManager")
	return int(sm.call("px", val)) if sm and sm.has_method("px") else roundi(val)


func _sz(val: float) -> float:
	var sm := get_node_or_null("/root/UIScaleManager")
	return float(sm.call("sz", val)) if sm and sm.has_method("sz") else val


func _sz2(w: float, h: float) -> Vector2:
	var sm := get_node_or_null("/root/UIScaleManager")
	return sm.call("sz2", w, h) if sm and sm.has_method("sz2") else Vector2(w, h)


func _on_scale_changed(_s: float) -> void:
	var ch := _sz(BASE_CARDS_HALF_H)
	_cards_box.offset_top    = -ch
	_cards_box.offset_bottom =  ch
	_cards_box.offset_left   = _sz(BASE_CARDS_MARGIN)
	_cards_box.offset_right  = _cards_box.offset_left + _sz(BASE_CARDS_WIDTH)
	var tw := _sz(BASE_TOAST_HALF_W)
	var th := _sz(BASE_TOAST_HALF_H)
	_toast.offset_left   = -tw
	_toast.offset_top    = -th
	_toast.offset_right  =  tw
	_toast.offset_bottom =  th
	for c: Control in _base_sizes:
		var base: Array = _base_sizes[c]
		c.custom_minimum_size = _sz2(base[0].x, base[0].y)
		c.add_theme_font_size_override(_font_key(c), _px(base[1]))


func _collect_base_sizes(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			_base_sizes[c] = [c.custom_minimum_size, c.get_theme_font_size(_font_key(c))]
		_collect_base_sizes(c)


func _font_key(c: Control) -> String:
	return "normal_font_size" if c is RichTextLabel else "font_size"


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func setup_players(player_list: Array) -> void:
	_round_panel.visible = true
	_lives.clear()
	for card: Control in _cards_nodes:
		card.visible = false
	for entry: Dictionary in player_list:
		var pid: int = int(entry["id"])
		var card: Control = _get_card(pid)
		if card == null:
			continue
		card.visible = true
		var color: Color = player_color(pid)
		(card.get_node("HBox/Stripe") as ColorRect).color = color
		var face_bg := StyleBoxFlat.new()
		face_bg.bg_color = color.darkened(0.45)
		face_bg.border_color = color.lightened(0.2)
		face_bg.set_border_width_all(3)
		face_bg.set_corner_radius_all(40)
		(card.get_node("HBox/FaceBg") as PanelContainer).add_theme_stylebox_override("panel", face_bg)
		(card.get_node("HBox/FaceBg/Face") as TextureRect).texture = _face(pid)
		var title := card.get_node("HBox/Info/Header/Title") as Label
		title.add_theme_color_override("font_color", color.lightened(0.4))
		title.text = GameManager.player_name(pid)
		_lives[pid] = PlayerScript.DEFAULT_LIVES
	_goal_label.text = _goal_text()
	_refresh_cards()


## Panel pytania gracza (null dla botów).
func get_quiz_panel(pid: int) -> Control:
	return _quiz_panels[pid - 1] if pid >= 1 and pid <= _quiz_panels.size() else null


func player_color(pid: int) -> Color:
	return PLAYER_COLORS[clampi(pid - 1, 0, PLAYER_COLORS.size() - 1)]


func update_lives(pid: int, lives_left: int) -> void:
	_lives[pid] = lives_left
	_render_hearts(pid)


## Serca (💀 po śmierci, w KILL odliczanie do odrodzenia) i zabójstwa „🎯 2/5”; wyszarzenie martwego.
func _render_hearts(pid: int, respawn_left: float = 0.0) -> void:
	var card: Control = _get_card(pid)
	if not card:
		return
	var lives: int = _lives.get(pid, 0)
	var text := "❤️".repeat(lives) if lives > 0 else "💀"
	if lives <= 0 and respawn_left > 0.0:
		text = BbI18n.tf("bb.hud.respawn_in", {"s": ceili(respawn_left)}, "💀 ↺ {s} s")
	if GameManager.is_kill_mode():
		text += "   " + BbI18n.tf("bb.hud.kills", {"kills": RoundManager.get_kills(pid), "goal": GameManager.kills_to_win}, "🎯 {kills}/{goal}")
	(card.get_node("HBox/Info/HeartsLabel") as Label).text = text
	card.modulate = Color(1, 1, 1, 0.55) if lives <= 0 else Color.WHITE


## Gwiazdki wygranych rund i korona lidera sesji na wszystkich kartach.
func _refresh_cards() -> void:
	var best := 0
	var leaders := 0
	for pid in _lives:
		var w := RoundManager.get_wins(pid)
		if w > best:
			best = w
			leaders = 1
		elif w == best and w > 0:
			leaders += 1
	for pid in _lives:
		var card := _get_card(pid)
		var wins := RoundManager.get_wins(pid)
		(card.get_node("HBox/Info/WinsLabel") as Label).text = _stars(wins)
		(card.get_node("HBox/Info/Header/Crown") as Label).visible = leaders == 1 and wins == best and best > 0
		_render_hearts(pid)


func _stars(wins: int) -> String:
	if GameManager.win_condition == GameManager.WinCondition.FIRST_TO_X and GameManager.rounds_to_win <= MAX_STARS:
		return "★".repeat(wins) + "☆".repeat(maxi(GameManager.rounds_to_win - wins, 0))
	if GameManager.win_condition == GameManager.WinCondition.FIRST_TO_X:
		return "★ %d/%d" % [wins, GameManager.rounds_to_win]
	return "★ %d" % wins


## Opis celu meczu pod zegarem, np. „💣 Ostatni żywy · do 3 wygranych”.
func _goal_text() -> String:
	var first := GameManager.win_condition == GameManager.WinCondition.FIRST_TO_X
	var n: int = GameManager.rounds_to_win if first else GameManager.max_rounds
	var key := "bb.hud.goal_%s_%s" % ["kill" if GameManager.is_kill_mode() else "last", "first" if first else "most"]
	return BbI18n.tf(key, {"n": n, "k": GameManager.kills_to_win}, key)


func _on_kills_changed(_pid: int, _kills: int) -> void:
	for pid in _lives:
		_render_hearts(pid)


func _on_round_started(_n: int) -> void:
	_overtime_shown = false
	_refresh_cards()


func update_player(pid: int, bombs: int, bomb_range: int, speed_mult: float,
		kick: bool = false, shield: bool = false) -> void:
	var card: Control = _get_card(pid)
	if not card:
		return
	var speed_level := roundi((speed_mult - 1.0) / PlayerScript.SPEED_STEP) + 1
	var line := "%s[b]%d[/b] %s[b]%d[/b] %s[b]%d[/b]" % [_icon("bomb_up"), bombs, _icon("range_up"), bomb_range, _icon("speed_up"), speed_level]
	if kick:
		line += "  " + _icon("kick")
	if shield:
		line += " " + _icon("shield")
	(card.get_node("HBox/Info/StatsLabel") as RichTextLabel).text = line


## Twarz gracza: pierwsza klatka arkusza postaci (stoi, przodem); bez pliku — null.
func _face(pid: int) -> Texture2D:
	var path := BBRuntime.path("resources/sprites/players/player_%d.png" % pid)
	if not ResourceLoader.exists(path):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = Rect2(Vector2.ZERO, atlas.atlas.get_size() / Vector2(PlayerScript.SHEET_COLS, PlayerScript.SHEET_ROWS))
	return atlas


## Ikona power-upu w BBCode (ta sama grafika co na planszy); bez pliku — emoji.
func _icon(kind: String) -> String:
	var path := BBRuntime.path("resources/sprites/objects/powerup_%s.png" % kind)
	if ResourceLoader.exists(path):
		var px := _px(21)
		return "[img=%dx%d]%s[/img]" % [px, px, path]
	return ICON_FALLBACK.get(kind, "?")


## Panel rundy: numer, zegar do nagłej śmierci (pomarańczowy pod koniec, czerwony i pulsujący w nagłej śmierci)
## i odliczanie odrodzenia na kartach w trybie KILL.
func _process(_delta: float) -> void:
	if not visible or not _round_panel.visible:
		return
	_round_label.text = BbI18n.tf("bb.hud.round", {"round": RoundManager.current_round}, "Runda {round}")
	var color := COLOR_TIMER
	if RoundManager.overtime:
		_timer_label.text = BbI18n.t("bb.hud.overtime_short", "⏱ Dogrywka")
		color = COLOR_TIMER_WARN
		if not _overtime_shown:
			_overtime_shown = true
			show_message(BbI18n.t("bb.hud.overtime", "⏱ Dogrywka — następne zabójstwo wygrywa!"), 3.0)
	elif RoundManager.sudden_death:
		_timer_label.text = BbI18n.t("bb.hud.sudden_short", "☠ Nagła śmierć")
		color = COLOR_TIMER_DANGER
		_timer_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 150.0)
	else:
		var left := ceili(RoundManager.time_left())
		_timer_label.text = "%d:%02d" % [left / 60, left % 60]
		if left <= TIMER_WARN_SECONDS:
			color = COLOR_TIMER_WARN
		_timer_label.modulate.a = 1.0
	_timer_label.add_theme_color_override("font_color", color)
	_timer_label.add_theme_font_size_override("font_size", _px(26 if RoundManager.sudden_death or RoundManager.overtime else 40))
	if GameManager.is_kill_mode():
		for p in get_tree().get_nodes_in_group("players"):
			if p.is_respawning():
				_render_hearts(p.player_id, p.respawn_time_left())


func show_message(msg: String, duration: float = 2.0) -> void:
	_toast.text = msg
	_toast.modulate.a = 1.0
	var tw: Tween = create_tween()
	tw.tween_interval(maxf(duration - 0.5, 0.1))
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_card(pid: int) -> Control:
	var idx: int = pid - 1
	if idx < 0 or idx >= _cards_nodes.size():
		return null
	return _cards_nodes[idx]


func _on_state_changed(_old: int, new_state: int) -> void:
	var gm = get_node_or_null("/root/GameManager")
	var playing_state : int = gm.get("GameState").PLAYING if gm and "GameState" in gm else 1
	visible = new_state == playing_state
