extends Node

## Główny menedżer gry BitBomber.
## Zarządza stanami gry i przejściami między nimi.

enum GameState {
	MENU,
	PLAYING,
	QUIZ_POWERUP,    # gracz zebrał ? power-up
	QUIZ_LAST_CHANCE, # gracz zginął — szansa na respawn
	ROUND_END,
	GAME_OVER
}

signal state_changed(old_state: GameState, new_state: GameState)

var current_state: GameState = GameState.MENU

## Konfiguracja sesji (ustawiana przed startem gry)
var num_human_players: int = 1  # 1 lub 2
var num_bots: int = 1           # dopełnienie do 2+ graczy na planszy
var rounds_to_win: int = 3      # ile rund wygrywa mecz


func change_state(new_state: GameState) -> void:
	var old = current_state
	current_state = new_state
	state_changed.emit(old, new_state)


func is_playing() -> bool:
	return current_state == GameState.PLAYING


func is_in_quiz() -> bool:
	return current_state in [GameState.QUIZ_POWERUP, GameState.QUIZ_LAST_CHANCE]


func start_game(human_players: int = 1, bots: int = 1) -> void:
	num_human_players = human_players
	num_bots = bots
	RoundManager.reset_session()
	change_state(GameState.PLAYING)
	get_tree().change_scene_to_file("res://scenes/maps/arena.tscn")


func go_to_menu() -> void:
	change_state(GameState.MENU)
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")
