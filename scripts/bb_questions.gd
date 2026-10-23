extends RefCounted

## Losowanie pytań z wybranego zestawu (GameManager.selected_quiz_id, "" = wszystkie) przez QuizManager.
## Zakres trudności zależy od trudności botów; łatwiejsze z zakresu wypadają częściej.

## Pytania „na szybko” w trakcie gry — da się odpowiedzieć klawiszem 1–4.
const CHOICE_TYPES : Array = ["multiple_choice", "true_false"]
## Wagi kolejnych poziomów trudności w zakresie (od najłatwiejszego)
const DIFF_WEIGHTS : Array[int] = [2, 3, 1]


static func pick(allowed_types: Array = []) -> Dictionary:
	var gm := _node("GameManager")
	var qm := _node("QuizManager")
	if qm == null:
		return {}
	var range_v := diff_range()
	var sel_id: String = gm.selected_quiz_id if gm else ""
	var all_ids: Array = qm.get_quiz_ids() if sel_id == "" or sel_id == "Wszystkie" else [sel_id]
	var valid_questions : Array = []
	var diffs_available : Array[int] = []
	for quiz_id in all_ids:
		for q in qm.get_questions(quiz_id, range_v, 999, allowed_types):
			if not allowed_types.is_empty() and not q.get("type", "multiple_choice") in allowed_types:
				continue
			valid_questions.append(q)
			var d : int = q.get("difficulty", 1)
			if not d in diffs_available:
				diffs_available.append(d)
	if valid_questions.is_empty():
		return {}
	diffs_available.sort()
	var max_available_diff: int = diffs_available.back()
	if max_available_diff < range_v.x:
		range_v.y = max_available_diff
		range_v.x = maxi(1, max_available_diff - (DIFF_WEIGHTS.size() - 1))
	var pool : Array = []
	for q in valid_questions:
		var d : int = q.get("difficulty", 1)
		if d >= range_v.x and d <= range_v.y:
			var w_idx := d - range_v.x
			for _i in range(DIFF_WEIGHTS[w_idx] if w_idx < DIFF_WEIGHTS.size() else 1):
				pool.append(q)
	if pool.is_empty():
		return valid_questions.pick_random()
	return pool.pick_random()


static func diff_range() -> Vector2i:
	var gm := _node("GameManager")
	match gm.bot_difficulty if gm else 0:
		0: return Vector2i(1, 3)
		2: return Vector2i(3, 5)
		_: return Vector2i(2, 4)


## Treść pytania i odpowiedzi do wyświetlenia (true_false: Prawda / Fałsz).
static func text_of(q: Dictionary) -> String:
	if q.get("type", "") == "true_false":
		return str(q.get("statement", ""))
	return str(q.get("question", q.get("prompt", "")))


static func answers_of(q: Dictionary) -> Array:
	if q.get("type", "") == "true_false":
		return [BbI18n.t("bb.quiz.true", "Prawda"), BbI18n.t("bb.quiz.false", "Fałsz")]
	return q.get("answers", [])


static func correct_index(q: Dictionary) -> int:
	if q.get("type", "") == "true_false":
		return 0 if bool(q.get("correct_answer", false)) else 1
	return int(q.get("correct_index", -1))


static func is_correct(q: Dictionary, index: int) -> bool:
	return index == correct_index(q)


## Czy jest sens dawać quiz w trakcie gry (power-up „quiz”): quizy włączone i są pytania z wyborem.
static func choice_quiz_available() -> bool:
	return not quizless_mode() and not pick(CHOICE_TYPES).is_empty()


## Ustawienie „bez quizów” (host: SettingsService, samodzielnie: SettingsManager).
static func quizless_mode() -> bool:
	var host_settings: Node = _node("SettingsService")
	if host_settings and host_settings.has_method("is_quizless_mode_enabled"):
		return bool(host_settings.call("is_quizless_mode_enabled"))

	for key_name: String in ["quizless_mode", "disable_quizzes", "skip_quizzes"]:
		var value: Variant = null
		if host_settings:
			if host_settings.has_method("get_global"):
				value = host_settings.call("get_global", key_name, null)
			elif host_settings.has_method("get_module"):
				value = host_settings.call("get_module", "bitbomber", key_name, null)
			if value != null:
				return bool(value)

		var local_settings: Node = _node("SettingsManager")
		if local_settings:
			if local_settings.has_method("get_global"):
				value = local_settings.call("get_global", key_name, null)
			else:
				value = local_settings.get(key_name)
			if value != null:
				return bool(value)

	return false


static func _node(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree else null
