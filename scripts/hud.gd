extends CanvasLayer

## HUD — UI zdefiniowane w hud.tscn, skrypt tylko wypełnia dane.
##
## Publiczne API:
##   hud.setup_players(player_list: Array)
##   hud.update_lives(pid, lives_left)
##   hud.update_player(pid, bombs, bomb_range, speed_mult, kick, shield)
##   hud.show_message(text, duration)

const PlayerScript = preload("player.gd")

const PLAYER_COLORS: Array[Color] = [
	Color(0.18, 0.45, 0.85),
	Color(0.88, 0.25, 0.55),
	Color(0.20, 0.65, 0.25),
	Color(0.55, 0.82, 0.20),
]

# Bazy z hud.tscn
const BASE_DOT_SIZE    := Vector2(14.0, 14.0)
const BASE_FONT_TITLE  := 22.0
const BASE_FONT_ROUND  := 25.0
const BASE_FONT_HEARTS := 20.0
const BASE_FONT_STATS  := 20.0
const BASE_FONT_TOAST  := 26.0
const BASE_CARDS_WIDTH := 270.0 

const BASE_CARDS_HALF_H  := 413.0   # offset_top = -413, offset_bottom = 413
const BASE_SEP_CARDS     := 6       # separation między kartami
const BASE_SEP_VBOX      := 6       # separation wewnątrz VBox karty
const BASE_SEP_HEADER    := 6       # separation w HBoxContainer Header
const BASE_TOAST_HALF_W  := 240.0   # offset_left = -240, offset_right = 240
const BASE_TOAST_HALF_H  := 40.0    # offset_top  =  -40, offset_bottom =  40

@onready var _cards_nodes: Array[Control] = [
	$Root/Cards/Card1,
	$Root/Cards/Card2,
	$Root/Cards/Card3,
	$Root/Cards/Card4,
]
@onready var _cards_box   : VBoxContainer  = $Root/Cards
@onready var _round_label : Label          = $Root/Cards/RoundPanel/RoundLabel
@onready var _toast       : Label          = $Root/ToastLabel
@onready var _round_panel : PanelContainer = $Root/Cards/RoundPanel


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
	for card: Control in _cards_nodes:
		card.visible = false
	_round_panel.visible = false
	visible = false
	$"Root/Cards".alignment = BoxContainer.ALIGNMENT_CENTER
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
	# Cards VBoxContainer — pionowe wycentrowanie i odstęp między kartami
	var ch := _sz(BASE_CARDS_HALF_H)
	_cards_box.offset_top    = -ch
	_cards_box.offset_bottom =  ch
	_cards_box.add_theme_constant_override("separation", _px(BASE_SEP_CARDS))
	_cards_box.offset_right = _sz(BASE_CARDS_WIDTH)
	
	# RoundLabel
	_round_label.add_theme_font_size_override("font_size", _px(BASE_FONT_ROUND))

	# ToastLabel
	var tw := _sz(BASE_TOAST_HALF_W)
	var th := _sz(BASE_TOAST_HALF_H)
	_toast.offset_left   = -tw
	_toast.offset_top    = -th
	_toast.offset_right  =  tw
	_toast.offset_bottom =  th
	_toast.add_theme_font_size_override("font_size", _px(BASE_FONT_TOAST))

	# Karty gracza
	var fs_btn := _px(BASE_FONT_TITLE)
	for card: Control in _cards_nodes:
		var vbox := card.get_node("VBox") as VBoxContainer
		vbox.add_theme_constant_override("separation", _px(BASE_SEP_VBOX))
		var header := vbox.get_node("Header") as HBoxContainer
		header.add_theme_constant_override("separation", _px(BASE_SEP_HEADER))
		(vbox.get_node("Header/Title") as Label).add_theme_font_size_override(
				"font_size", fs_btn)
		(vbox.get_node("HeartsLabel") as Label).add_theme_font_size_override(
				"font_size", _px(BASE_FONT_HEARTS))
		(vbox.get_node("StatsLabel") as Label).add_theme_font_size_override(
				"font_size", _px(BASE_FONT_STATS))
		(vbox.get_node("Header/Dot") as ColorRect).custom_minimum_size = \
				_sz2(BASE_DOT_SIZE.x, BASE_DOT_SIZE.y)


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func setup_players(player_list: Array) -> void:
	_round_panel.visible = true
	for card: Control in _cards_nodes:
		card.visible = false
	for entry: Dictionary in player_list:
		var pid: int = int(entry["id"])
		var idx: int = pid - 1
		if idx < 0 or idx >= _cards_nodes.size():
			continue
		var card: Control = _cards_nodes[idx]
		card.visible = true
		var color: Color = PLAYER_COLORS[clamp(idx, 0, PLAYER_COLORS.size() - 1)]
		(card.get_node("VBox/Header/Dot") as ColorRect).color = color
		(card.get_node("VBox/Header/Title") as Label).text = BbI18n.tf("bb.hud.player_title", {"player": pid})


func update_lives(pid: int, lives_left: int) -> void:
	_lives[pid] = lives_left
	_render_hearts(pid)


## Życia, a w trybie KILL też zabójstwa „🎯:2/5”.
func _render_hearts(pid: int) -> void:
	var card: Control = _get_card(pid)
	if not card:
		return
	var text := "❤️:%d" % _lives.get(pid, 0)
	var gm := get_node_or_null("/root/GameManager")
	var rm := get_node_or_null("/root/RoundManager")
	if gm and rm and gm.is_kill_mode():
		text += "  " + BbI18n.tf("bb.hud.kills", {"kills": rm.get_kills(pid), "goal": gm.kills_to_win}, "🎯:{kills}/{goal}")
	(card.get_node("VBox/HeartsLabel") as Label).text = text


func _on_kills_changed(_pid: int, _kills: int) -> void:
	for pid in _lives:
		_render_hearts(pid)


func _on_round_started(_n: int) -> void:
	_overtime_shown = false
	for pid in _lives:
		_render_hearts(pid)


func update_player(pid: int, bombs: int, bomb_range: int, speed_mult: float,
		kick: bool = false, shield: bool = false) -> void:
	var card: Control = _get_card(pid)
	if not card:
		return
	var speed_level := roundi((speed_mult - 1.0) / PlayerScript.SPEED_STEP) + 1
	var extras := ("🦶" if kick else "") + ("🛡" if shield else "")
	(card.get_node("VBox/StatsLabel") as Label).text = \
		"💣:%d\n↔️:%d\n⚡:%d\n%s" % [bombs, bomb_range, speed_level, extras]


## Panel rundy: numer + czas do nagłej śmierci (wcześniej zawsze „Runda 1” — nikt nie wołał update_round).
func _process(_delta: float) -> void:
	if not visible or not _round_panel.visible:
		return
	var rm := get_node_or_null("/root/RoundManager")
	if rm == null:
		return
	var round_num : int = rm.current_round
	if rm.overtime:
		_round_label.text = BbI18n.tf("bb.hud.round_overtime", {"round": round_num}, "Runda {round} · dogrywka")
		if not _overtime_shown:
			_overtime_shown = true
			show_message(BbI18n.t("bb.hud.overtime", "⏱ Dogrywka — następne zabójstwo wygrywa!"), 3.0)
	elif rm.sudden_death:
		_round_label.text = BbI18n.tf("bb.hud.round_sudden", {"round": round_num}, "Runda {round} · ☠")
	else:
		var left := ceili(rm.time_left())
		_round_label.text = BbI18n.tf("bb.hud.round_timer",
				{"round": round_num, "time": "%d:%02d" % [left / 60, left % 60]}, "Runda {round} · {time}")


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
