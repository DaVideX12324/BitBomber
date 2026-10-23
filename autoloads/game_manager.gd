extends Node

const BBRuntime = preload("../scripts/bb_runtime.gd")

## Główny menedżer gry BitBomber.
## Zarządza stanami gry i przejściami między nimi.

var debug_enabled: bool = true # Zmień na false, aby wyciszyć całą grę

enum GameState {
	MENU,
	PLAYING,
	QUIZ_LAST_CHANCE,
	ROUND_END,
	GAME_OVER
}

enum WinCondition {
	FIRST_TO_X,    ## Wygrywa ten, kto pierwszy zdobędzie X rund
	MOST_WINS_IN_Y ## Wygrywa ten, kto ma więcej wygranych po Y rundach
}

enum GameMode {
	LAST_STANDING, ## Ostatni żywy wygrywa rundę (zabici czekają do następnej, poza ostatnią szansą)
	KILL,          ## Zabici odradzają się; rundę wygrywa pierwszy z kills_to_win zabójstwami (Kill z Bomb It)
}

signal state_changed(old_state: GameState, new_state: GameState)

var current_state: GameState = GameState.MENU

var num_human_players: int = 1
var num_bots: int = 1
var rounds_to_win: int = 3   ## Używane w trybie FIRST_TO_X
var max_rounds: int = 5      ## Używane w trybie MOST_WINS_IN_Y (max 20)
var selected_quiz_id: String = ""
## Id mapy z resources/maps ("" = losowa co rundę)
var selected_map: String = ""
## Szansa na skrzynkę na polu 'b' mapy (Bomb It: 0,6–0,8 arcade, 0,5 kill)
var box_density: float = 0.7

## Poziom trudności botów: 0=Easy 1=Medium 2=Hard (mapowane na BotAI.Difficulty)
var bot_difficulty: int = 0

## Warunek wygranej sesji
var win_condition: WinCondition = WinCondition.FIRST_TO_X

var game_mode: GameMode = GameMode.LAST_STANDING
## Tryb KILL: tyle zabójstw wygrywa rundę
var kills_to_win: int = 5

## Referencja do persistentnego roota (ustawiana przez game.gd)
var game_node: Node = null

## Tryb embedded: null = standalone, Node = host modułu
var host_module: Node = null
## Sesję ustawił host (session_config) — po niej wyjście do hosta zamiast menu BitBombera.
var host_session: bool = false


func is_embedded() -> bool:
	return host_module != null


func change_state(new_state: GameState) -> void:
	var old := current_state
	current_state = new_state
	state_changed.emit(old, new_state)


func is_playing() -> bool:
	return current_state == GameState.PLAYING


func is_kill_mode() -> bool:
	return game_mode == GameMode.KILL


func is_in_quiz() -> bool:
	return current_state == GameState.QUIZ_LAST_CHANCE


func total_players() -> int:
	return num_human_players + num_bots


## Gracze 1..num_human_players to ludzie, kolejne ID to boty.
func is_bot_id(player_id: int) -> bool:
	return player_id > num_human_players


## „Gracz 2” albo „Bot 1” (boty numerowane od 1, niezależnie od liczby ludzi).
func player_name(player_id: int) -> String:
	if is_bot_id(player_id):
		return BbI18n.tf("bb.hud.bot_title", {"n": player_id - num_human_players}, "Bot {n}")
	return BbI18n.tf("bb.hud.player_title", {"player": player_id}, "Gracz {player}")


func start_game(human_players: int = 1, bots: int = 1) -> void:
	num_human_players = human_players
	num_bots = bots
	RoundManager.reset_session()
	change_state(GameState.PLAYING)
	if game_node:
		game_node.load_arena()
	else:
		get_tree().change_scene_to_file(BBRuntime.path("scenes/maps/arena.tscn"))


## Ustawienia sesji z hosta (ModuleHostApi.session_config) i od razu start gry. Klucze: README, „Sesja z hosta”.
func start_from_config(config: Dictionary) -> void:
	var humans := clampi(int(config.get("humans", 1)), 1, 2)
	var bots := clampi(int(config.get("bots", 1)), 0, 4 - humans)
	if humans + bots < 2:
		bots = 1
	game_mode = GameMode.KILL if str(config.get("mode", "")) == "kill" else GameMode.LAST_STANDING
	box_density = float(config.get("box_density", 0.5 if game_mode == GameMode.KILL else 0.7))
	kills_to_win = maxi(int(config.get("kills_to_win", kills_to_win)), 1)
	bot_difficulty = clampi(int(config.get("difficulty", bot_difficulty)), 0, 2)
	selected_map = str(config.get("map", ""))
	selected_quiz_id = str(config.get("quiz_id", selected_quiz_id))
	if config.has("max_rounds"):
		win_condition = WinCondition.MOST_WINS_IN_Y
		max_rounds = clampi(int(config["max_rounds"]), 1, 20)
	else:
		win_condition = WinCondition.FIRST_TO_X
		rounds_to_win = clampi(int(config.get("rounds_to_win", rounds_to_win)), 1, 20)
	host_session = true
	start_game(humans, bots)


## Wynik sesji dla hosta (ModuleHostApi.finish_session); winner_id -1 = remis.
func build_session_result(winner_id: int) -> Dictionary:
	var players: Array = []
	var correct := 0
	var wrong := 0
	for pid in range(1, total_players() + 1):
		var a: Dictionary = RoundManager.get_answers(pid)
		correct += int(a["correct"])
		wrong += int(a["wrong"])
		players.append({
			"id": pid, "name": player_name(pid), "is_bot": is_bot_id(pid),
			"round_wins": RoundManager.get_wins(pid), "correct": a["correct"], "wrong": a["wrong"],
		})
	var rounds := RoundManager.current_round
	var summary: String
	if winner_id > 0:
		summary = BbI18n.tf("bb.result.summary_win", {"name": player_name(winner_id), "rounds": rounds},
				"{name} wygrał · rundy: {rounds}")
	else:
		summary = BbI18n.tf("bb.result.summary_draw", {"rounds": rounds}, "Remis · rundy: {rounds}")
	if correct + wrong > 0:
		summary += BbI18n.tf("bb.result.summary_quiz", {"correct": correct, "total": correct + wrong},
				" · quiz {correct}/{total}")
	return {
		"completed": true,
		"mode": "kill" if is_kill_mode() else "last_standing",
		"rounds_played": rounds,
		"winner": {"id": winner_id, "name": player_name(winner_id), "is_bot": is_bot_id(winner_id)} if winner_id > 0 else null,
		"players": players,
		"answers": {"correct": correct, "wrong": wrong},
		"duration_s": snappedf(RoundManager.session_duration(), 0.1),
		"summary": summary,
	}


func go_to_menu() -> void:
	if host_session:
		host_session = false
		exit_game()
		return
	change_state(GameState.MENU)
	if game_node:
		game_node.load_menu()
	else:
		get_tree().change_scene_to_file(BBRuntime.path("scenes/ui/main_menu.tscn"))


func exit_game() -> void:
	change_state(GameState.MENU)
	if is_embedded():
		host_module.emit_signal("exit_requested")
	else:
		get_tree().quit()


func log_debug(message: Variant, category: String = "GENERAL") -> void:
	if OS.is_debug_build(): # Zwraca true tylko w edytorze i debugowych buildach
		print("[%s] %s" % [category.to_upper(), str(message)])
