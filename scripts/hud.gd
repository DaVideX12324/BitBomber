extends CanvasLayer

## HUD węzeł — układ wzorowany na Bomb It 7:
##   - Lewa strona ekranu: pionowa lista kart graczy (P1..P4)
##   - Każda karta: kolorowe tło, numer gracza, serca, statystyki
##   - Na górze środka: "Runda X"
##   - Toast/wiadomości na środku ekranu
##
## Publiczne API:
##   hud.setup_players(player_list: Array)
##     player_list = [{ "id":1, "is_bot":false }, ...]
##   hud.update_lives(pid, lives_left, max_lives)
##   hud.update_player(pid, bombs, bomb_range, speed)
##   hud.update_round(round_num)
##   hud.show_message(text, duration)

const PLAYER_COLORS: Array[Color] = [
	Color(0.18, 0.45, 0.85),
	Color(0.88, 0.25, 0.55),
	Color(0.20, 0.65, 0.25),
	Color(0.55, 0.82, 0.20),
]

const CARD_WIDTH   : int = 160
const CARD_HEIGHT  : int = 140
const CARD_MARGIN  : int = 6
const CARD_PADDING : int = 8

var _root        : Control
var _round_label : Label
var _cards       : Dictionary = {}


func _ready() -> void:
	layer = 10
	_build_root()
	GameManager.state_changed.connect(_on_state_changed)


# ---------------------------------------------------------------------------
# BUDOWANIE UI
# ---------------------------------------------------------------------------

func _build_root() -> void:
	_root = Control.new()
	_root.set_anchor_and_offset(SIDE_LEFT,   0.0, 0)
	_root.set_anchor_and_offset(SIDE_RIGHT,  1.0, 0)
	_root.set_anchor_and_offset(SIDE_TOP,    0.0, 0)
	_root.set_anchor_and_offset(SIDE_BOTTOM, 1.0, 0)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var round_bg : PanelContainer = PanelContainer.new()
	round_bg.set_anchor_and_offset(SIDE_LEFT,   0.5, -80)
	round_bg.set_anchor_and_offset(SIDE_RIGHT,  0.5,  80)
	round_bg.set_anchor_and_offset(SIDE_TOP,    0.0,   6)
	round_bg.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  38)
	round_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(round_bg)

	_round_label = Label.new()
	_round_label.text = "Runda 1"
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 16)
	round_bg.add_child(_round_label)


## Tworzy lub odtwarza karty graczy na podstawie listy.
func setup_players(player_list: Array) -> void:
	for pid: int in _cards:
		if is_instance_valid(_cards[pid]["panel"]):
			(_cards[pid]["panel"] as Node).queue_free()
	_cards.clear()

	var sorted: Array = player_list.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))

	for i: int in sorted.size():
		var pdata: Dictionary = sorted[i] as Dictionary
		var pid: int = int(pdata["id"])
		_create_player_card(pid, i)


func _create_player_card(pid: int, index: int) -> void:
	var color_idx: int    = clamp(pid - 1, 0, PLAYER_COLORS.size() - 1)
	var card_color: Color = PLAYER_COLORS[color_idx]
	var y_offset: int     = CARD_MARGIN + index * (CARD_HEIGHT + CARD_MARGIN)

	var outer: PanelContainer = PanelContainer.new()
	outer.set_anchor_and_offset(SIDE_LEFT,   0.0, CARD_MARGIN)
	outer.set_anchor_and_offset(SIDE_RIGHT,  0.0, CARD_MARGIN + CARD_WIDTH)
	outer.set_anchor_and_offset(SIDE_TOP,    0.0, y_offset)
	outer.set_anchor_and_offset(SIDE_BOTTOM, 0.0, y_offset + CARD_HEIGHT)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(card_color.r * 0.45, card_color.g * 0.45, card_color.b * 0.45, 0.92)
	style.border_width_left   = 3
	style.border_width_right  = 3
	style.border_width_top    = 3
	style.border_width_bottom = 3
	style.border_color = card_color
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left   = CARD_PADDING
	style.content_margin_right  = CARD_PADDING
	style.content_margin_top    = CARD_PADDING
	style.content_margin_bottom = CARD_PADDING
	outer.add_theme_stylebox_override("panel", style)
	_root.add_child(outer)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	outer.add_child(vbox)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var dot: ColorRect = ColorRect.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.color = card_color
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(dot)

	var name_lbl: Label = Label.new()
	name_lbl.text = "Gracz %d" % pid
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var sep: HSeparator = HSeparator.new()
	var sep_style: StyleBoxFlat = StyleBoxFlat.new()
	sep_style.bg_color = Color(card_color.r, card_color.g, card_color.b, 0.5)
	sep_style.content_margin_top    = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	var hearts_lbl: Label = Label.new()
	hearts_lbl.text = "❤️ ❤️ ❤️"
	hearts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hearts_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(hearts_lbl)

	var stats_lbl: Label = Label.new()
	stats_lbl.text = "💣 : 1\n🎯 : 2\n⚡ : 1.0x"
	stats_lbl.add_theme_font_size_override("font_size", 12)
	stats_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(stats_lbl)

	_cards[pid] = {
		"panel":        outer,
		"hearts_label": hearts_lbl,
		"stats_label":  stats_lbl,
		"name_label":   name_lbl,
	}


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func update_lives(pid: int, lives_left: int, max_lives: int = 3) -> void:
	if not _cards.has(pid):
		return
	var hearts: PackedStringArray = PackedStringArray()
	for i: int in max_lives:
		hearts.append("❤️" if i < lives_left else "🖤")
	(_cards[pid]["hearts_label"] as Label).text = " ".join(hearts)


func update_player(pid: int, bombs: int, bomb_range: int, speed: float) -> void:
	if not _cards.has(pid):
		_create_player_card(pid, pid - 1)
	(_cards[pid]["stats_label"] as Label).text = "💣 : %d\n🎯 : %d\n⚡ : %.1fx" % [bombs, bomb_range, speed]


func update_round(round_num: int) -> void:
	if _round_label:
		_round_label.text = "Runda %d" % round_num


func show_message(msg: String, duration: float = 2.0) -> void:
	var lbl: Label = Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	lbl.set_anchor_and_offset(SIDE_LEFT,   0.5, -240)
	lbl.set_anchor_and_offset(SIDE_RIGHT,  0.5,  240)
	lbl.set_anchor_and_offset(SIDE_TOP,    0.5,  -40)
	lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.5,   40)
	_root.add_child(lbl)
	var tw: Tween = create_tween()
	tw.tween_interval(duration - 0.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	await tw.finished
	lbl.queue_free()


# ---------------------------------------------------------------------------
# Reakcja na zmianę stanu gry
# ---------------------------------------------------------------------------

func _on_state_changed(_old: GameManager.GameState, new_state: GameManager.GameState) -> void:
	visible = new_state == GameManager.GameState.PLAYING
