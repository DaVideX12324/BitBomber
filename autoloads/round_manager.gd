extends Node

## Zarządza rundami, wynikami graczy i triggerami quizów.

signal round_started(round_number: int)
signal round_ended(winner_id: int)   # -1 = remis / timeout
signal quiz_powerup_triggered(collector_id: int)
signal last_chance_triggered(dead_player_id: int)
signal last_chance_resolved(dead_player_id: int, respawned: bool)
signal session_ended(winner_id: int)

## Wyniki rund per gracz (player_id -> liczba wygranych rund)
var round_wins: Dictionary = {}
var current_round: int = 0
var _last_chance_player_id: int = -1

## Czas trwania rundy w sekundach (0 = bez limitu)
var round_time_limit: float = 180.0
var _round_timer: float = 0.0
var _round_active: bool = false


func _process(delta: float) -> void:
	if not _round_active or round_time_limit <= 0.0:
		return
	_round_timer += delta
	if _round_timer >= round_time_limit:
		_timeout_round()


# ---------------------------------------------------------------------------
# Sesja
# ---------------------------------------------------------------------------

func reset_session() -> void:
	round_wins.clear()
	current_round = 0
	_round_active = false
	_round_timer = 0.0


# ---------------------------------------------------------------------------
# Rundy
# ---------------------------------------------------------------------------

func start_round() -> void:
	current_round += 1
	_round_timer = 0.0
	_round_active = true
	round_started.emit(current_round)


func end_round(winner_id: int) -> void:
	if not _round_active:
		return
	_round_active = false

	if winner_id >= 1:
		round_wins[winner_id] = round_wins.get(winner_id, 0) + 1

	# Najpierw ustal czy sesja się kończy
	var session_winner := _compute_session_winner(winner_id)

	# Zmień stan na ROUND_END (death_screen będzie wiedział że to normalny koniec rundy)
	GameManager.change_state(GameManager.GameState.ROUND_END)

	# Emituj round_ended — death_screen pokazuje ekran z przyciskiem
	round_ended.emit(winner_id)

	# Jeśli sesja się skończyła — zmień stan i emituj session_ended (nadpisze ekran)
	if session_winner != 0:
		GameManager.change_state(GameManager.GameState.GAME_OVER)
		session_ended.emit(session_winner)


## Zwraca ID zwycięzcy sesji (>0) lub remis (-1), lub 0 jeśli sesja trwa nadal.
func _compute_session_winner(winner_id: int) -> int:
	var wc := GameManager.win_condition

	if wc == GameManager.WinCondition.FIRST_TO_X:
		if winner_id >= 1 and round_wins.get(winner_id, 0) >= GameManager.rounds_to_win:
			return winner_id

	elif wc == GameManager.WinCondition.MOST_WINS_IN_Y:
		if current_round >= GameManager.max_rounds:
			var best_id   := -1
			var best_wins := -1
			var tie       := false
			for pid in round_wins:
				var w: int = round_wins[pid]
				if w > best_wins:
					best_wins = w
					best_id   = pid
					tie       = false
				elif w == best_wins:
					tie = true
			return -1 if tie else best_id

	return 0  # sesja trwa nadal


func _timeout_round() -> void:
	_round_active = false
	end_round(-1)


# ---------------------------------------------------------------------------
# Quiz — power-up
# ---------------------------------------------------------------------------

func trigger_powerup_quiz(collector_id: int) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	GameManager.change_state(GameManager.GameState.QUIZ_POWERUP)
	quiz_powerup_triggered.emit(collector_id)


# ---------------------------------------------------------------------------
# Quiz — last chance
# ---------------------------------------------------------------------------

func trigger_last_chance(dead_player_id: int) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_last_chance_player_id = dead_player_id
	GameManager.change_state(GameManager.GameState.QUIZ_LAST_CHANCE)
	last_chance_triggered.emit(dead_player_id)


func resolve_last_chance(respawned: bool) -> void:
	var pid := _last_chance_player_id
	_last_chance_player_id = -1
	last_chance_resolved.emit(pid, respawned)
	GameManager.change_state(GameManager.GameState.PLAYING)


func resolve_powerup_quiz() -> void:
	GameManager.change_state(GameManager.GameState.PLAYING)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func get_wins(player_id: int) -> int:
	return round_wins.get(player_id, 0)


func get_last_chance_player() -> int:
	return _last_chance_player_id


func rounds_remaining() -> int:
	match GameManager.win_condition:
		GameManager.WinCondition.FIRST_TO_X:
			var best := 0
			for pid in round_wins:
				if round_wins[pid] > best:
					best = round_wins[pid]
			return GameManager.rounds_to_win - best
		GameManager.WinCondition.MOST_WINS_IN_Y:
			return GameManager.max_rounds - current_round
		_:
			return 0
