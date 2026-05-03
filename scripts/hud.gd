extends CanvasLayer

## HUD — UI zdefiniowane w hud.tscn, skrypt tylko wypełnia dane.
##
## Publiczne API:
##   hud.setup_players(player_list: Array)
##     player_list = [{ "id":1, "is_bot":false }, ...]
##   hud.update_lives(pid, lives_left)
##   hud.update_player(pid, bombs, bomb_range, speed)
##   hud.update_round(round_num)
##   hud.show_message(text, duration)

const PLAYER_COLORS: Array[Color] = [
	Color(0.18, 0.45, 0.85),
	Color(0.88, 0.25, 0.55),
	Color(0.20, 0.65, 0.25),
	Color(0.55, 0.82, 0.20),
]

@onready var _cards_nodes: Array[Control] = [
	$Root/Cards/Card1,
	$Root/Cards/Card2,
	$Root/Cards/Card3,
	$Root/Cards/Card4,
]
@onready var _round_label : Label = $Root/RoundPanel/RoundLabel
@onready var _toast       : Label = $Root/ToastLabel


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	for card: Control in _cards_nodes:
		card.visible = false


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func setup_players(player_list: Array) -> void:
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
		(card.get_node("VBox/Header/Title") as Label).text = "Gracz %d" % pid


## Aktualizuje serca gracza — format: "❤️:N"
func update_lives(pid: int, lives_left: int) -> void:
	var card: Control = _get_card(pid)
	if not card:
		return
	(card.get_node("VBox/HeartsLabel") as Label).text = "\u2764\ufe0f:%d" % lives_left


## Aktualizuje statystyki gracza pid.
func update_player(pid: int, bombs: int, bomb_range: int, speed: float) -> void:
	var card: Control = _get_card(pid)
	if not card:
		return
	var speed_level := int((speed - 1.0) / 50.0) + 1
	(card.get_node("VBox/StatsLabel") as Label).text = \
		"\uD83D\uDCA3:%d\n\uD83C\uDFAF:%d\n\u26A1:%d\n" % [bombs, bomb_range, speed_level]


## Aktualizuje numer rundy.
func update_round(round_num: int) -> void:
	_round_label.text = "Runda %d" % round_num


## Wyświetla toast pośrodku ekranu.
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


func _on_state_changed(_old: GameManager.GameState, new_state: GameManager.GameState) -> void:
	visible = new_state == GameManager.GameState.PLAYING
