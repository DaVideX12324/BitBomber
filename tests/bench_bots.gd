extends SceneTree

## Benchmark AI botów: 4 boty w trybie KILL (bez limitu zabójstw i czasu) przez BENCH_SECONDS sekund gry.
## Wypisuje zabójstwa, samobójstwa (własna bomba lub nieznany sprawca) i zebrane power-upy.
## godot --headless --path <host> --fixed-fps 60 -s res://modules/BitBomber/tests/bench_bots.gd
## env: BENCH_SECONDS (300), BENCH_DIFF (1), BENCH_MAP (classic)

const BBRuntime = preload("../scripts/bb_runtime.gd")

var _kills := 0
var _suicides := 0
var _items := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var seconds := int(OS.get_environment("BENCH_SECONDS")) if OS.has_environment("BENCH_SECONDS") else 300
	var diff := int(OS.get_environment("BENCH_DIFF")) if OS.has_environment("BENCH_DIFF") else 1
	var module: Node = load(BBRuntime.path("module_root.tscn")).instantiate()
	root.add_child(module)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var rm: Node = root.get_node("RoundManager")
	gm.debug_enabled = OS.has_environment("BENCH_TRACE")
	gm.selected_map = OS.get_environment("BENCH_MAP") if OS.has_environment("BENCH_MAP") else "classic"
	gm.bot_difficulty = diff
	gm.game_mode = gm.GameMode.KILL
	gm.box_density = 0.5
	gm.kills_to_win = 9999
	gm.start_game(0, 4)
	rm.round_time_limit = 99999.0
	await process_frame
	for p in get_nodes_in_group("players"):
		p.killed.connect(func(v: int, k: int):
			if k == v or k <= 0:
				_suicides += 1
				if OS.has_environment("BENCH_WHY"):
					print("SUICIDE ", _why(p))
			else: _kills += 1)
		p.powerup_collected.connect(func(_pid: int, _t: String): _items += 1)
	for i in seconds * 60:
		await physics_frame
	var deaths := _kills + _suicides
	print("BENCH diff=%d s=%d deaths=%d kills=%d suicides=%d (%.0f%%) items=%d" % [
		diff, seconds, deaths, _kills, _suicides, 100.0 * _suicides / maxi(deaths, 1), _items])
	quit()


## Stan bota w chwili samobójstwa (BENCH_WHY=1): stan AI, długość ścieżki, czy stał w zagrożeniu przed śmiercią.
func _why(p: Node) -> String:
	var ai: Node = p.get_node_or_null("BotAI")
	if ai == null:
		return "brak AI"
	var bombs: Array[String] = []
	var me: Vector2i = ai._cell(p.global_position)
	for b in get_nodes_in_group("bomb"):
		var bc: Vector2i = ai._cell(b.global_position)
		if absi(bc.x - me.x) + absi(bc.y - me.y) <= 6:
			bombs.append("%s r%d %s%s" % [bc, b.explosion_range, "własna " if b.owner_player == p else "",
					"%.2fs" % b.time_left() if b.has_method("time_left") else ""])
	var fire: Array[String] = []
	for e in get_nodes_in_group("explosion"):
		var ec: Vector2i = ai._cell(e.global_position)
		if absi(ec.x - me.x) + absi(ec.y - me.y) <= 1:
			fire.append(str(ec))
	return "bot=%d state=%s at=%s px=%s path=%s complete=%s fire=[%s] bombs=[%s]" % [p.player_id, ai.BotState.keys()[ai.current_state], me,
			p.global_position.round(), ai.current_path, ai._action_complete, ", ".join(fire), ", ".join(bombs)]
