extends SceneTree

## Quiz w trakcie gry: odrodzenie przez quiz (KILL — dobrze: od razu z tarczą, źle: po 3 s),
## pytanie-bonus (źle: spowolnienie) i bot, który sam „odpowiada”.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_field_quiz.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")
const BbQuestions = preload("../scripts/bb_questions.gd")

var _failed := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		_failed += 1


func _player(pid: int) -> Node:
	for p in get_nodes_in_group("players"):
		if p.player_id == pid:
			return p
	return null


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Odpowiedź gracza pid: dobra albo pierwsza zła — przez akcję wejścia, jak z klawiatury.
func _answer(fq: Node, pid: int, good: bool) -> void:
	var q: Dictionary = fq._active[pid]["q"]
	var idx: int = BbQuestions.correct_index(q)
	if not good:
		idx = 1 if idx == 0 else 0
	var ev := InputEventAction.new()
	ev.action = "quiz_p%d_%s" % [pid, ["a", "b", "c", "d"][idx]]
	ev.pressed = true
	root.push_input(ev)


func _run() -> void:
	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	gm.selected_map = "classic"
	gm.game_mode = gm.GameMode.KILL
	gm.kills_to_win = 10
	gm.start_game(2, 1)
	await _frames(10)
	var fq: Node = gm.game_node.get_node("FieldQuiz")
	var hud: Node = gm.game_node.get_node("HUD")
	var p1 := _player(1)
	var p2 := _player(2)
	var bot := _player(3)
	bot._frozen = true   # bot stoi — nie miesza w zabójstwach

	# --- Odrodzenie, dobra odpowiedź ---
	p1.take_hit(2)
	await process_frame
	_check(fq.is_asking(1) and hud.get_quiz_panel(1).visible, "po śmierci P1 pytanie odrodzenia w panelu")
	_check(p1.is_respawning(), "P1 czeka na odrodzenie")
	_answer(fq, 1, true)
	await _frames(40)
	_check(p1.is_alive and p1.has_shield, "dobra odpowiedź → P1 wraca od razu z tarczą (alive %s, tarcza %s)" % [p1.is_alive, p1.has_shield])

	# --- Odrodzenie, zła odpowiedź ---
	p2.take_hit(1)
	await process_frame
	_answer(fq, 2, false)
	await _frames(150)   # 2,5 s
	_check(not p2.is_alive, "zła odpowiedź → P2 po 2,5 s jeszcze czeka")
	await _frames(60)
	_check(p2.is_alive and not p2.has_shield, "zła odpowiedź → P2 wraca po 3 s bez tarczy")

	# --- Pytanie-bonus, zła odpowiedź ---
	p1.apply_powerup("quiz")
	_check(fq.is_asking(1), "power-up ❓ → pytanie-bonus")
	await process_frame
	_answer(fq, 1, false)
	await process_frame
	_check(p1._slow_time > 0.0, "zła odpowiedź na bonus → spowolnienie")
	await _frames(120)
	_check(not hud.get_quiz_panel(1).visible, "panel znika po wyniku")

	# --- Bot ---
	bot.apply_powerup("quiz")
	_check(fq.is_asking(3), "bot dostał pytanie-bonus")
	await _frames(int(fq.BOT_THINK.y * 60) + 10)
	_check(not fq.is_asking(3), "bot odpowiedział sam")

	var a: Dictionary = rm.get_answers(1)
	_check(a["correct"] == 1 and a["wrong"] == 1 and rm.get_answers(3)["correct"] + rm.get_answers(3)["wrong"] == 0,
			"statystyki odpowiedzi tylko ludzi: P1 %s" % [a])

	print("ALL OK" if _failed == 0 else "FAILED %d" % _failed)
	quit(_failed)
