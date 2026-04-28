extends Node

## Zarządza bazą pytań quizowych, ładowaniem z JSON i walidacją odpowiedzi.
## Oddziela warstwę merytoryczną od prezentacji — pytania ładowane z plików JSON.
##
## Obsługiwane typy pytań (pole "type" w JSON):
##   "multiple_choice" — klasyczny wybór jednej z N odpowiedzi (domyślny)
##   "true_false"      — prawda / fałsz
##   "fill_tiles"      — uzupełnianie luk kafelkami z puli
##   "fill_text"       — wpisanie słowa/frazy (z opcjonalnym prefilled_pattern)
##   "matching"        — łączenie lewej i prawej kolumny w pary
##
## Format answer_current() — player_answer: Dictionary:
##   multiple_choice : { "index": int }
##   true_false      : { "value": bool }
##   fill_text       : { "text": String }
##   fill_tiles      : { "placements": { "0": "wartość", "1": "wartość", ... } }
##   matching        : { "pairs": [ { "left_index": int, "right_index": int }, ... ] }

signal quiz_loaded(quiz_id: String)
signal question_answered(correct: bool, question_data: Dictionary)
signal quiz_completed(quiz_id: String, score: int, total: int)

var _quizzes: Dictionary = {}            # quiz_id -> Array[Dictionary]
var _answered_questions: Dictionary = {} # question_id -> { "correct": int, "wrong": int }
var _current_quiz_id: String = ""
var _current_questions: Array = []
var _current_question_index: int = 0
var _current_score: int = 0


func _ready() -> void:
	_load_all_quizzes()


# ---------------------------------------------------------------------------
# Ładowanie quizów
# ---------------------------------------------------------------------------

## Ładuje wszystkie pliki .json z folderu res://resources/quizzes/
func _load_all_quizzes() -> void:
	var dir = DirAccess.open("res://resources/quizzes/")
	if not dir:
		push_warning("QuizManager: Brak folderu quizzes!")
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var quiz_id = file_name.get_basename()
			_load_quiz_file("res://resources/quizzes/" + file_name, quiz_id)
		file_name = dir.get_next()
	dir.list_dir_end()
	print("QuizManager: Załadowano %d quizów" % _quizzes.size())


func _load_quiz_file(path: String, quiz_id: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("QuizManager: Nie można otworzyć %s" % path)
		return

	var json = JSON.new()
	var result = json.parse(file.get_as_text())
	file.close()

	if result != OK:
		push_warning("QuizManager: Błąd parsowania %s" % path)
		return

	var data = json.data
	if data is Dictionary and data.has("questions"):
		_quizzes[quiz_id] = data["questions"]
	elif data is Array:
		_quizzes[quiz_id] = data


# ---------------------------------------------------------------------------
# Pobieranie pytań
# ---------------------------------------------------------------------------

## Zwraca przefiltrowana i przetasowana listę pytań.
## allowed_types — pusta tablica = wszystkie typy; np. ["multiple_choice", "true_false"]
func get_questions(
	quiz_id: String,
	difficulty_range: Vector2i = Vector2i(1, 5),
	count: int = 5,
	allowed_types: Array = []
) -> Array:
	if not _quizzes.has(quiz_id):
		push_warning("QuizManager: Quiz '%s' nie istnieje" % quiz_id)
		return []

	var all_questions: Array = _quizzes[quiz_id]
	var filtered: Array = []

	for q in all_questions:
		var diff = q.get("difficulty", 1)
		var qtype = q.get("type", "multiple_choice")
		var diff_ok = diff >= difficulty_range.x and diff <= difficulty_range.y
		var type_ok = allowed_types.is_empty() or (qtype in allowed_types)
		if diff_ok and type_ok:
			filtered.append(q)

	filtered.shuffle()
	if filtered.size() > count:
		filtered.resize(count)

	return filtered


# ---------------------------------------------------------------------------
# Przepływ quizu
# ---------------------------------------------------------------------------

## Rozpoczyna quiz — zwraca pierwsze pytanie lub {} jeśli brak pytań.
func start_quiz(
	quiz_id: String,
	difficulty_range: Vector2i = Vector2i(1, 5),
	count: int = 5,
	allowed_types: Array = []
) -> Dictionary:
	_current_questions = get_questions(quiz_id, difficulty_range, count, allowed_types)
	_current_quiz_id = quiz_id
	_current_question_index = 0
	_current_score = 0

	if _current_questions.is_empty():
		return {}

	quiz_loaded.emit(quiz_id)
	return _current_questions[0]


## Sprawdza odpowiedź na bieżące pytanie.
## player_answer: Dictionary — format zależy od pola "type" pytania (patrz nagłówek).
## Zwraca słownik z wynikiem lub {} jeśli quiz już skończony.
func answer_current(player_answer: Dictionary) -> Dictionary:
	if _current_question_index >= _current_questions.size():
		return {}

	var question = _current_questions[_current_question_index]
	var correct := _check_answer(question, player_answer)

	if correct:
		_current_score += 1

	# Zapis statystyk pytania
	var qid = question.get("id", "unknown")
	if not _answered_questions.has(qid):
		_answered_questions[qid] = { "correct": 0, "wrong": 0 }
	if correct:
		_answered_questions[qid]["correct"] += 1
	else:
		_answered_questions[qid]["wrong"] += 1

	question_answered.emit(correct, question)

	_current_question_index += 1

	if _current_question_index >= _current_questions.size():
		quiz_completed.emit(_current_quiz_id, _current_score, _current_questions.size())

	return {
		"correct": correct,
		"question_type": question.get("type", "multiple_choice"),
		"correct_index": question.get("correct_index", 0),
		"correct_answer": question.get("correct_answer", null),
		"answer": question.get("answer", ""),
		"gaps": question.get("gaps", []),
		"pairs": question.get("pairs", []),
		"explanation": question.get("explanation", ""),
		"quiz_finished": _current_question_index >= _current_questions.size(),
		"score": _current_score,
		"total": _current_questions.size(),
	}


## Zwraca bieżące pytanie bez przesuwania indeksu.
func get_current_question() -> Dictionary:
	if _current_question_index < _current_questions.size():
		return _current_questions[_current_question_index]
	return {}


func get_quiz_ids() -> Array:
	return _quizzes.keys()


# ---------------------------------------------------------------------------
# Sprawdzanie odpowiedzi — wewnętrzna logika per typ
# ---------------------------------------------------------------------------

func _check_answer(question: Dictionary, player_answer: Dictionary) -> bool:
	var qtype = question.get("type", "multiple_choice")

	match qtype:
		"multiple_choice":
			return player_answer.get("index", -1) == question.get("correct_index", -1)

		"true_false":
			return player_answer.get("value", null) == question.get("correct_answer", null)

		"fill_text":
			var given: String = player_answer.get("text", "").strip_edges()
			var expected: String = question.get("answer", "")
			if not question.get("case_sensitive", false):
				given = given.to_lower()
				expected = expected.to_lower()
			var alternatives: Array = question.get("accepted_alternatives", [])
			if not question.get("case_sensitive", false):
				alternatives = alternatives.map(func(a): return a.to_lower())
			return given == expected or given in alternatives

		"fill_tiles":
			var placements: Dictionary = player_answer.get("placements", {})
			var gaps: Array = question.get("gaps", [])
			for gap in gaps:
				var idx = str(gap.get("index", -1))
				if placements.get(idx, "") != gap.get("correct", ""):
					return false
			return true

		"matching":
			var player_pairs: Array = player_answer.get("pairs", [])
			var correct_pairs: Array = question.get("pairs", [])
			return _compare_pairs(player_pairs, correct_pairs)

		_:
			push_warning("QuizManager: Nieznany typ pytania '%s'" % qtype)
			return false


## Porównuje pary (kolejność nieistotna).
func _compare_pairs(player: Array, correct: Array) -> bool:
	if player.size() != correct.size():
		return false
	for pair in correct:
		var found := false
		for p in player:
			if p.get("left_index", -1) == pair.get("left_index", -1) \
			and p.get("right_index", -1) == pair.get("right_index", -1):
				found = true
				break
		if not found:
			return false
	return true


# ---------------------------------------------------------------------------
# Statystyki / adaptacyjna trudność
# ---------------------------------------------------------------------------

## Dokładność per kategoria (do DifficultyManager / własnych analiz)
func get_accuracy_for_category(category: String) -> float:
	var correct_count := 0
	var total_count := 0
	for quiz_id in _quizzes:
		for q in _quizzes[quiz_id]:
			if q.get("category", "") == category:
				var qid = q.get("id", "")
				if _answered_questions.has(qid):
					correct_count += _answered_questions[qid]["correct"]
					total_count += _answered_questions[qid]["correct"] + _answered_questions[qid]["wrong"]
	if total_count == 0:
		return 0.5
	return float(correct_count) / float(total_count)


func get_overall_accuracy() -> float:
	var correct_count := 0
	var total_count := 0
	for qid in _answered_questions:
		correct_count += _answered_questions[qid]["correct"]
		total_count += _answered_questions[qid]["correct"] + _answered_questions[qid]["wrong"]
	if total_count == 0:
		return 0.5
	return float(correct_count) / float(total_count)


# ---------------------------------------------------------------------------
# Zapis / Odczyt / Reset
# ---------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {
		"answered_questions": _answered_questions.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	_answered_questions = data.get("answered_questions", {})


func reset() -> void:
	_answered_questions.clear()
	_current_quiz_id = ""
	_current_questions.clear()
	_current_question_index = 0
	_current_score = 0
