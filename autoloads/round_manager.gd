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
	_round_active = false
	if winner_id >= 0:
		round_wins[winner_id] = round_wins.get(winner_id, 0) + 1
	round_ended.emit(winner_id)
	GameManager.change_state(GameManager.GameState.ROUND_END)
	_check_session_winner()


func _timeout_round() -> void:
	_round_active = false
	# Remis — nikt nie dostaje punktu
	end_round(-1)


func _check_session_winner() -> void:
	for player_id in round_wins:
		if round_wins[player_id] >= GameManager.rounds_to_win:
			session_ended.emit(player_id)
			return


# ---------------------------------------------------------------------------
# Quiz — power-up
# ---------------------------------------------------------------------------

## Wywołaj gdy gracz wejdzie na kafelek z ? power-upem.
## Pauzuje grę i triggeruje ekran quizu.
func trigger_powerup_quiz(collector_id: int) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	GameManager.change_state(GameManager.GameState.QUIZ_POWERUP)
	quiz_powerup_triggered.emit(collector_id)


# ---------------------------------------------------------------------------
# Quiz — last chance
# ---------------------------------------------------------------------------

## Wywołaj gdy ludzki gracz ginie.
## Pauzuje grę i triggeruje quiz last-chance.
## Boty NIE triggerują last-chance — giną od razu.
func trigger_last_chance(dead_player_id: int) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_last_chance_player_id = dead_player_id
	GameManager.change_state(GameManager.GameState.QUIZ_LAST_CHANCE)
	last_chance_triggered.emit(dead_player_id)


## Wywołaj z UI quizu po zakończeniu pytania last-chance.
## respawned=true  → gracz wraca; respawned=false → eliminacja.
func resolve_last_chance(respawned: bool) -> void:
	var pid = _last_chance_player_id
	_last_chance_player_id = -1
	last_chance_resolved.emit(pid, respawned)
	GameManager.change_state(GameManager.GameState.PLAYING)


## Wywołaj z UI quizu po zakończeniu pytania power-up.
func resolve_powerup_quiz() -> void:
	GameManager.change_state(GameManager.GameState.PLAYING)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func get_wins(player_id: int) -> int:
	return round_wins.get(player_id, 0)


func get_last_chance_player() -> int:
	return _last_chance_player_id
