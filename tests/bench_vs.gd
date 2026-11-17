extends SceneTree

## Benchmark trudności botów: gracz 1 to bot TRUDNY (zastępca sprawnego gracza), reszta to boty BENCH_DIFF.
## Tryb Ostatni żywy, BENCH_ROUNDS rund na zmianę map; wypisuje, jaką część rund wygrał trudny bot.
## Same boty: po pierwszej śmierci gra od razu włącza nagłą śmierć (game.gd) — tak samo w każdej próbie.
## Przy równych botach wyszedłby udział ~1 / liczba graczy — im więcej ponad to, tym słabsze boty BENCH_DIFF.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/bench_vs.gd
## env: BENCH_DIFF (0), BENCH_BOTS (3 = przeciwników trudnego), BENCH_ROUNDS (20), BENCH_MAP ("" = losowa)

const BBRuntime = preload("../scripts/bb_runtime.gd")
const HARD := 2

var _wins := {}
var _rounds := 0
var _draws := 0
var _suicides := 0
var _round_over := false


func _initialize() -> void:
	_run()


func _run() -> void:
	var diff := int(OS.get_environment("BENCH_DIFF")) if OS.has_environment("BENCH_DIFF") else 0
	var opponents := int(OS.get_environment("BENCH_BOTS")) if OS.has_environment("BENCH_BOTS") else 3
	var rounds := int(OS.get_environment("BENCH_ROUNDS")) if OS.has_environment("BENCH_ROUNDS") else 20
	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	gm.selected_map = OS.get_environment("BENCH_MAP") if OS.has_environment("BENCH_MAP") else ""
	gm.bot_difficulty = diff
	gm.game_mode = gm.GameMode.LAST_STANDING
	gm.rounds_to_win = 9999
	rm.round_ended.connect(func(w: int):
		_round_over = true
		if w < 0:
			_draws += 1
		else:
			_wins[w] = int(_wins.get(w, 0)) + 1)
	gm.start_game(0, opponents + 1)
	for r in rounds:
		await process_frame
		await process_frame   # AI botów powstaje odroczone (player._init_ai)
		_make_hard(1)
		for p in get_nodes_in_group("players"):
			if not p.killed.is_connected(_on_killed):
				p.killed.connect(_on_killed)
		_round_over = false
		var frames := 0
		while not _round_over and frames < 60 * 600:
			await physics_frame
			frames += 1
			if OS.has_environment("BENCH_VERBOSE") and frames % 3600 == 0:
				var info: Array[String] = []
				for p in get_nodes_in_group("players"):
					var ai: Node = p.get("_ai")
					info.append("%d:%s%s %s" % [p.player_id, "A" if p.is_alive else "x", "" if ai else "(bez AI)", p.global_position.round()])
				print("  t=%ds bomby=%d %s" % [frames / 60, get_nodes_in_group("bomb").size(), ", ".join(info)])
		_rounds += 1
		if OS.has_environment("BENCH_VERBOSE"):
			print("runda %d: %.1f s, stan=%d, wygrane=%s" % [r + 1, frames / 60.0, gm.current_state, _wins])
		if r < rounds - 1:
			paused = false   # jak „Następna runda” na ekranie końca rundy (death_screen._on_continue)
			gm.change_state(gm.GameState.PLAYING)
			gm.game_node.next_round()
	var hard_wins := int(_wins.get(1, 0))
	print("BENCH_VS diff=%d przeciwnicy=%d rundy=%d trudny=%d (%.0f%%, równo byłoby %.0f%%) remisy=%d samobójstwa=%d wygrane=%s" % [
		diff, opponents, _rounds, hard_wins, 100.0 * hard_wins / maxi(_rounds, 1), 100.0 / (opponents + 1),
		_draws, _suicides, _wins])
	quit()


func _on_killed(victim: int, killer: int) -> void:
	if killer == victim or killer <= 0:
		_suicides += 1


## Bot gracza 1 dostaje profil TRUDNY (profil czyta się raz w _ready, więc wpisy ładujemy od nowa).
func _make_hard(player_id: int) -> void:
	for p in get_nodes_in_group("players"):
		if p.player_id != player_id:
			continue
		var ai: Node = p.get("_ai")   # nowy węzeł AI co rundę (stary jeszcze w kolejce do usunięcia → inna nazwa)
		if not is_instance_valid(ai) or int(ai.difficulty) == HARD:
			return
		ai._entries.clear()
		ai.difficulty = HARD
		ai._apply_profile()
		ai._cur_entry = ai._default_entry
