extends Node

## Adaptacyjna trudność — dostosowuje poziom pytań do umiejętności gracza.
## śledzi wyniki per kategoria i globalnie.

signal difficulty_adjusted(category: String, new_level: int)

# Zakres trudności: 1 (łatwe) do 5 (bardzo trudne)
const MIN_DIFFICULTY := 1
const MAX_DIFFICULTY := 5
const WINDOW_SIZE := 10  # Ilość ostatnich odpowiedzi do analizy

# Progi adaptacji
const THRESHOLD_UP := 0.8    # Powyżej 80% poprawnych → zwiększ trudność
const THRESHOLD_DOWN := 0.4  # Poniżej 40% poprawnych → zmniejsz trudność

# Bieżące poziomy trudności per kategoria
var _difficulty_levels: Dictionary = {}  # category -> int
var _recent_answers: Dictionary = {}     # category -> Array[bool] (ostatnie odpowiedzi)


## Zwraca aktualny poziom trudności dla kategorii
func get_difficulty(category: String) -> int:
	return _difficulty_levels.get(category, 2)  # Domyślnie średnia trudność


## Zwraca zakres trudności (Vector2i) do przekazania QuizManagerowi
func get_difficulty_range(category: String) -> Vector2i:
	var base = get_difficulty(category)
	var low = maxi(base - 1, MIN_DIFFICULTY)
	var high = mini(base + 1, MAX_DIFFICULTY)
	return Vector2i(low, high)


## Rejestruje wynik odpowiedzi i dostosowuje trudność
func record_answer(category: String, correct: bool) -> void:
	if not _recent_answers.has(category):
		_recent_answers[category] = []

	_recent_answers[category].append(correct)

	# Ogranicz do ostatnich WINDOW_SIZE
	if _recent_answers[category].size() > WINDOW_SIZE:
		_recent_answers[category].pop_front()

	# Sprawdź czy trzeba zmienić trudność
	_evaluate_difficulty(category)


func _evaluate_difficulty(category: String) -> void:
	var answers: Array = _recent_answers.get(category, [])
	if answers.size() < 5:
		return  # Za mało danych

	var correct_count := 0
	for a in answers:
		if a:
			correct_count += 1

	var accuracy = float(correct_count) / float(answers.size())
	var current = get_difficulty(category)
	var new_diff = current

	if accuracy >= THRESHOLD_UP and current < MAX_DIFFICULTY:
		new_diff = current + 1
		_recent_answers[category].clear()  # Reset po zmianie
	elif accuracy <= THRESHOLD_DOWN and current > MIN_DIFFICULTY:
		new_diff = current - 1
		_recent_answers[category].clear()

	if new_diff != current:
		_difficulty_levels[category] = new_diff
		difficulty_adjusted.emit(category, new_diff)
		print("DifficultyManager: %s → poziom %d (accuracy: %.0f%%)" % [category, new_diff, accuracy * 100])


## Globalna trudność (średnia ze wszystkich kategorii)
func get_global_difficulty() -> float:
	if _difficulty_levels.is_empty():
		return 2.0
	var total := 0
	for cat in _difficulty_levels:
		total += _difficulty_levels[cat]
	return float(total) / float(_difficulty_levels.size())


## --- Zapis/Odczyt ---
func get_save_data() -> Dictionary:
	return {
		"difficulty_levels": _difficulty_levels.duplicate(),
		"recent_answers": _recent_answers.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	_difficulty_levels = data.get("difficulty_levels", {})
	_recent_answers = data.get("recent_answers", {})


func reset() -> void:
	_difficulty_levels.clear()
	_recent_answers.clear()
