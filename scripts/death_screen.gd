extends CanvasLayer

## Death / Round-end / Game-over overlay.
##
## Tryby działania (ustawiane przez show_*):
##   LAST_CHANCE  — gracz zginął, może odpowiedzieć na quiz aby respawnować
##   ROUND_END    — runda skończyła się, można przejść dalej
##   GAME_OVER    — cała sesja zakończona, wróć do menu
##
## Slot na quiz:
##   quiz_slot (VBoxContainer) jest domyślnie ukryty.
##   Aby dodać quiz: wypełnij quiz_slot swoimi węzłami i ustaw quiz_slot.visible = true
##   przed wywołaniem show_last_chance().

enum Mode { LAST_CHANCE, ROUND_END, GAME_OVER }

@onready var _overlay    : ColorRect      = $Overlay
@onready var _icon       : Label          = $Panel/VBox/Icon
@onready var _title      : Label          = $Panel/VBox/Title
@onready var _subtitle   : Label          = $Panel/VBox/Subtitle
@onready var _quiz_slot  : VBoxContainer  = $Panel/VBox/QuizSlot
@onready var _btn_cont   : Button         = $Panel/VBox/Buttons/BtnContinue
@onready var _btn_menu   : Button         = $Panel/VBox/Buttons/BtnMenu

var _mode: Mode = Mode.ROUND_END
var _dead_player_id: int = -1


func _ready() -> void:
	_btn_cont.pressed.connect(_on_continue)
	_btn_menu.pressed.connect(_on_menu)

	# Podłączenie do sygnałów
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
	# session_ended obsługuje game over — tu tylko round end
	if winner_id >= 1:
		show_round_end(winner_id)
	else:
		show_round_end_draw()


func _on_session_ended(winner_id: int) -> void:
	show_game_over(winner_id)


# ---------------------------------------------------------------------------
# Publiczne show_* — można wywołać ręcznie lub przez quiz system
# ---------------------------------------------------------------------------

func show_last_chance(dead_player_id: int) -> void:
	_mode = Mode.LAST_CHANCE
	_dead_player_id = dead_player_id
	_icon.text = "💥"
	_title.text = "Gracz %d zginął!" % dead_player_id
	_subtitle.text = "Ostatnia szansa na respawn."
	_btn_cont.text = "Respawnuj"
	_btn_menu.visible = false
	## HOOK: tu można wstrzynąć pytanie quizowe
	## quiz_slot.visible = true  ← odkomentuj gdy będzie quiz
	_show()


func show_round_end(winner_id: int) -> void:
	_mode = Mode.ROUND_END
	_icon.text = "🏆"
	_title.text = "Gracz %d wygrał rundę!" % winner_id
	_subtitle.text = _build_score_text()
	_btn_cont.text = "Następna runda"
	_btn_menu.visible = true
	_show()


func show_round_end_draw() -> void:
	_mode = Mode.ROUND_END
	_icon.text = "⏳"
	_title.text = "Remis!"
	_subtitle.text = _build_score_text()
	_btn_cont.text = "Następna runda"
	_btn_menu.visible = true
	_show()


func show_game_over(winner_id: int) -> void:
	_mode = Mode.GAME_OVER
	_icon.text = "🌟"
	_title.text = "Gracz %d wygrał mecz!" % winner_id
	_subtitle.text = _build_score_text()
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
			# bez quizu — od razu respawn
			RoundManager.resolve_last_chance(true)
			_hide()
		Mode.ROUND_END:
			_hide()
			# Przeładuj arenę na nową rundę
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
	for pid in [1, 2]:
		var w := RoundManager.get_wins(pid)
		lines.append("Gracz %d: %d rund" % [pid, w])
	return "\n".join(lines)


func _show() -> void:
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)


func _hide() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	await tw.finished
	visible = false
	_quiz_slot.visible = false
	_btn_cont.visible = true
	_btn_menu.visible = true
