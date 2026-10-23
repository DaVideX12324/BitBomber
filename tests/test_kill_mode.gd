extends SceneTree

## Tryb KILL: 2 graczy stoi na spawnach, bomby P1 przy P2 → zabójstwo, odrodzenie, druga → koniec rundy.
## Potem: koniec czasu przy remisie → dogrywka.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_kill_mode.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _failed := 0
var _winner := -100
var _killed: Array = []


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


func _bomb_on(owner: Node, target: Node) -> void:
	var bomb: Node2D = load(BBRuntime.path("scenes/objects/bomb.tscn")).instantiate()
	bomb.explosion_range = 1
	bomb.owner_player = owner
	bomb.position = target.global_position
	root.get_node("GameManager").game_node._current_map.add_child(bomb)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	rm.round_ended.connect(func(w: int): _winner = w)
	gm.selected_map = "classic"
	gm.game_mode = gm.GameMode.KILL
	gm.kills_to_win = 2
	gm.start_game(2, 0)
	await _frames(10)
	var p1 := _player(1)
	var p2 := _player(2)
	p2.killed.connect(func(v: int, k: int): _killed.append([v, k]))

	_bomb_on(p1, p2)
	await _frames(150)
	_check(_killed == [[2, 1]], "P2 zabity przez P1: %s" % [_killed])
	_check(rm.get_kills(1) == 1, "P1 ma 1 zabójstwo")
	_check(not p2.is_alive, "P2 czeka na odrodzenie")
	# Człowiek dostaje pytanie odrodzenia (field_quiz.gd); bez odpowiedzi wraca po czasie pytania.
	var fq: Node = gm.game_node.get_node("FieldQuiz")
	var wait: float = fq.RESPAWN_TIME + 0.2 if fq.is_asking(2) else p2.KILL_RESPAWN_DELAY
	await _frames(int(wait * 60) + 10)
	_check(p2.is_alive and p2.visible, "P2 odrodzony (po %.1f s)" % wait)
	_check(_winner == -100, "runda trwa po 1 zabójstwie")

	await _frames(130)   # nieśmiertelność po odrodzeniu (2 s)
	_bomb_on(p1, p2)
	await _frames(150)
	_check(_winner == 1, "P1 wygrywa rundę przy 2 zabójstwach (zwycięzca %d)" % _winner)

	# Dogrywka: nowa runda, czas mija przy 0:0.
	paused = false   # ekran końca rundy pauzuje grę (jak przycisk „Dalej”)
	gm.change_state(gm.GameState.PLAYING)
	gm.game_node.next_round()
	_winner = -100
	rm.round_time_limit = 1.0
	await _frames(90)
	_check(rm.overtime and _winner == -100, "remis po czasie → dogrywka")
	await _frames(10)
	_bomb_on(p2, p1)
	await _frames(150)
	_check(_winner == 2, "dogrywka: pierwsze zabójstwo wygrywa (zwycięzca %d)" % _winner)

	rm.round_time_limit = 180.0
	gm.game_mode = gm.GameMode.LAST_STANDING
	print("FAILED: %d" % _failed if _failed else "ALL OK")
	quit(1 if _failed else 0)
