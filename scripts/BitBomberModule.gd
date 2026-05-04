extends Node
class_name BitBomberModule

## Warstwa API dla trybu embedded.
## Użycie z poziomu hosta (np. Artefakt Wiedzy):
##
##   var bb = preload("res://bitbomber/BitBomberModule.tscn").instantiate()
##   add_child(bb)
##   bb.exit_requested.connect(_on_bb_exit)
##   bb.session_finished.connect(_on_bb_done)
##   bb.start_session({ "players": 2, "bots": 0, "rounds_to_win": 3, "difficulty": 1 })

signal exit_requested
signal session_finished(result: Dictionary)


func start_session(config: Dictionary) -> void:
	GameManager.host_module       = self
	GameManager.num_human_players = config.get("players", 1)
	GameManager.num_bots          = config.get("bots", 1)
	GameManager.rounds_to_win     = config.get("rounds_to_win", 3)
	GameManager.bot_difficulty    = config.get("difficulty", 0)
	GameManager.start_game(
		GameManager.num_human_players,
		GameManager.num_bots
	)


func stop_session() -> void:
	GameManager.host_module = null
	GameManager.go_to_menu()


func _emit_session_finished(winner_id: int) -> void:
	session_finished.emit({
		"winner_id": winner_id,
		"rounds_p1": RoundManager.get_wins(1),
		"rounds_p2": RoundManager.get_wins(2)
	})
