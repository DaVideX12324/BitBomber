extends Node

## Główny menedżer gry BitBomber.
## Zarządza stanami gry i przejściami między nimi.

enum GameState {
	MENU,
	PLAYING,
	QUIZ_POWERUP,
	QUIZ_LAST_CHANCE,
	ROUND_END,
	GAME_OVER
}

signal state_changed(old_state: GameState, new_state: GameState)

var current_state: GameState = GameState.MENU

var num_human_players: int = 1
var num_bots: int = 1
var rounds_to_win: int = 3

## Poziom trudności botów: 0=Easy 1=Medium 2=Hard (mapowane na BotAI.Difficulty)
var bot_difficulty: int = 0

## Referencja do persistentnego roota (ustawiana przez game.gd)
var game_node: Node = null

## Tryb embedded: null = standalone, Node = host modułu
var host_module: Node = null


func is_embedded() -> bool:
	return host_module != null


func change_state(new_state: GameState) -> void:
	var old := current_state
	current_state = new_state
	state_changed.emit(old, new_state)


func is_playing() -> bool:
	return current_state == GameState.PLAYING


func is_in_quiz() -> bool:
	return current_state in [GameState.QUIZ_POWERUP, GameState.QUIZ_LAST_CHANCE]


func total_players() -> int:
	return num_human_players + num_bots


func start_game(human_players: int = 1, bots: int = 1) -> void:
	num_human_players = human_players
	num_bots = bots
	RoundManager.reset_session()
	change_state(GameState.PLAYING)
	if game_node:
		game_node.load_arena()
	else:
		get_tree().change_scene_to_file("res://scenes/maps/arena.tscn")


func go_to_menu() -> void:
	change_state(GameState.MENU)
	if is_embedded():
		host_module.emit_signal("exit_requested")
	elif game_node:
		game_node.load_menu()
	else:
		get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")
