extends SceneTree

## Wyniki: każdy bot ma własne wygrane rundy (bez wspólnego „999”), tabela pokazuje wszystkich graczy.
## Śmierć człowieka przy 2+ żywych botach → od razu nagła śmierć, runda trwa dalej.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/test_scores.gd

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _failed := 0
var _winner := -100


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


func _run() -> void:
	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	rm.round_ended.connect(func(w: int): _winner = w)
	gm.selected_map = "classic"
	gm.start_game(1, 3)
	await _frames(10)

	_check(gm.player_name(1) == "Gracz 1" and gm.player_name(3) == "Bot 2",
			"nazwy: %s / %s" % [gm.player_name(1), gm.player_name(3)])

	# Człowiek ginie, zostają 3 boty → nagła śmierć zamiast końca rundy.
	_player(1).crush()
	await _frames(5)
	_check(_winner == -100, "runda trwa po śmierci człowieka (zwycięzca %d)" % _winner)
	_check(rm.sudden_death, "same boty → nagła śmierć od razu")

	# Wygrywa bot 3 — zapis pod jego ID.
	rm.end_round(3)
	await process_frame
	_check(_winner == 3, "round_ended z ID bota (%d)" % _winner)
	_check(rm.get_wins(3) == 1 and not rm.round_wins.has(999), "wygrana zapisana botowi 3: %s" % [rm.round_wins])

	var ds: Node = gm.game_node.get_node("DeathScreen")
	var title: String = ds.get_node("Panel/VBox/Title").text
	_check(title.contains("Bot 2"), "tytuł: %s" % title)
	var rows: Array[String] = []
	for i in 4:
		var row: Label = ds.get_node("Panel/VBox/ScoreTable/ScoreRow%d" % i)
		if row.visible:
			rows.append(row.text)
	_check(rows.size() == 4, "4 wiersze tabeli: %s" % [rows])
	_check(rows.size() == 4 and rows[2].contains("Bot 2") and rows[2].contains("1"), "wiersz bota 2: %s" % (rows[2] if rows.size() > 2 else ""))
	_check(rows.size() == 4 and rows[0].contains("Gracz 1"), "wiersz gracza 1: %s" % (rows[0] if rows.size() > 0 else ""))

	print("ALL OK" if _failed == 0 else "FAILED %d" % _failed)
	paused = false
	quit(_failed)
