extends CanvasLayer

## Death / Round-end / Game-over overlay.
##
## Tryby działania:
##   LAST_CHANCE  — gracz zginął, może odpowiedzieć na quiz aby respawnować
##   ROUND_END    — runda skończyła się (tryb wielorundowy, bez botów)
##   GAME_OVER    — cała sesja zakończona (lub tryb z botami)

enum Mode { LAST_CHANCE, ROUND_END, GAME_OVER }

@onready var _overlay   : ColorRect      = $Overlay
@onready var _panel     : PanelContainer = $Panel
@onready var _icon      : Label          = $Panel/VBox/Icon
@onready var _title     : Label          = $Panel/VBox/Title
@onready var _subtitle  : Label          = $Panel/VBox/Subtitle
@onready var _quiz_slot : VBoxContainer  = $Panel/VBox/QuizSlot
@onready var _btn_cont  : Button         = $Panel/VBox/Buttons/BtnContinue
@onready var _btn_menu  : Button         = $Panel/VBox/Buttons/BtnMenu

var _mode: Mode = Mode.ROUND_END
var _dead_player_id: int = -1


func _ready() -> void:
	_btn_cont.pressed.connect(_on_continue)
	_btn_menu.pressed.connect(_on_menu)
	RoundManager.last_chance_triggered.connect(_on_last_chance)
	RoundManager.round_ended.connect(_on_round_ended)
	RoundManager.session_ended.connect(_on_session_ended)


# ---------------------------------------------------------------------------
# Sygnały z RoundManagera
# ---------------------------------------------------------------------------

func _on_last_chance(dead_player_id: int) -> void:
	_dead_player_id = dead_player_id
	show_last_chance(dead_player_id)


func _on_round_ended(winner_id: int) -> void:
	# W trybie z botami round_ended odpala się razem z session_ended —
	# obsługę przejmuje _on_session_ended, tutaj ignorujemy.
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return
	if winner_id >= 1:
		show_round_end(winner_id)
	else:
		show_round_end_draw()


func _on_session_ended(winner_id: int) -> void:
	show_game_over(winner_id)


# ---------------------------------------------------------------------------
# Publiczne show_*
# ---------------------------------------------------------------------------

func show_last_chance(dead_player_id: int) -> void:
	_mode = Mode.LAST_CHANCE
	_dead_player_id = dead_player_id
	_icon.text = "💥"
	_title.text = "Gracz %d zginął!" % dead_player_id
	_subtitle.text = "Ostatnia szansa na respawn."
	_btn_cont.text = "Respawnuj"
	_btn_cont.visible = true
	_btn_menu.visible = false
	_show()


func show_round_end(winner_id: int) -> void:
	_mode = Mode.ROUND_END
	_icon.text = "🏆"
	_title.text = "Gracz %d wygrał rundę!" % winner_id
	_subtitle.text = _build_score_text()
	_btn_cont.text = "Następna runda"
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()


func show_round_end_draw() -> void:
	_mode = Mode.ROUND_END
	_icon.text = "⏳"
	_title.text = "Remis!"
	_subtitle.text = _build_score_text()
	_btn_cont.text = "Następna runda"
	_btn_cont.visible = true
	_btn_menu.visible = true
	_show()


func show_game_over(winner_id: int) -> void:
	_mode = Mode.GAME_OVER
	if winner_id == -1:
		_icon.text = "⏳"
		_title.text = "Remis!"
		_subtitle.text = "Obaj gracze zginęli jednocześnie."
	elif winner_id == 0:
		# winner_id == 0 oznacza że wygrał bot (ostatni przy życiu)
		_icon.text = "🤖"
		_title.text = "Wygrał bot!"
		_subtitle.text = "Lepiej następnym razem."
	else:
		_icon.text = "🏆"
		_title.text = "Gracz %d wygrał!" % winner_id
		_subtitle.text = "Gratulacje!"
	_btn_cont.visible = false
	_btn_menu.visible = true
	_btn_menu.text = "Menu główne"
	_show()


# ---------------------------------------------------------------------------
# Przyciski
# ---------------------------------------------------------------------------

func _on_continue() -> void:
	match _mode:
		Mode.LAST_CHANCE:
			RoundManager.resolve_last_chance(true)
			_hide()
		Mode.ROUND_END:
			_hide()
			if GameManager.game_node:
				GameManager.game_node.load_arena()
			GameManager.change_state(GameManager.GameState.PLAYING)
		Mode.GAME_OVER:
			pass


func _on_menu() -> void:
	_hide()
	GameManager.go_to_menu()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _build_score_text() -> String:
	var lines: PackedStringArray = []
	for pid: int in [1, 2]:
		var w := RoundManager.get_wins(pid)
		lines.append("Gracz %d: %d rund" % [pid, w])
	return "\n".join(lines)


func _show() -> void:
	visible = true
	_overlay.modulate.a = 0.0
	_panel.modulate.a   = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.25)
	tw.tween_property(_panel,   "modulate:a", 1.0, 0.25)


func _hide() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "modulate:a", 0.0, 0.2)
	tw.tween_property(_panel,   "modulate:a", 0.0, 0.2)
	await tw.finished
	visible = false
	_quiz_slot.visible = false
	_btn_cont.visible  = true
	_btn_menu.visible  = true
