extends Node

## Persistentny root całej gry.
## Zarządza podmianą aktywnej subsceny (menu / arena) oraz:
## - spawnowaniem graczy i botów
## - podłączeniem HUDu do graczy
## - obsługą końca rundy (kto zginął, kto wygrał)

const PLAYER_SCENE = preload("res://scenes/players/player.tscn")

@onready var hud_1p : CanvasLayer = $HUD1P
@onready var hud_2p : CanvasLayer = $HUD2P

var _current_scene : Node  = null
var _players_root  : Node2D = null
var _arena         : Node2D = null
var _players       : Array  = []


func _ready() -> void:
	GameManager.game_node = self
	GameManager.state_changed.connect(_on_state_changed)
	_load_scene("res://scenes/menus/main_menu.tscn")


# ---------------------------------------------------------------------------
# Podmiana sceny
# ---------------------------------------------------------------------------

func _load_scene(path: String) -> void:
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null
	_arena        = null
	_players_root = null
	_players.clear()
	_current_scene = load(path).instantiate()
	add_child(_current_scene)
	move_child(_current_scene, 0)


func load_arena() -> void:
	_load_scene("res://scenes/maps/arena.tscn")
	_arena        = _current_scene as Node2D
	_players_root = Node2D.new()
	_players_root.name = "Players"
	_current_scene.add_child(_players_root)
	_spawn_players()
	RoundManager.start_round()
	RoundManager.last_chance_resolved.connect(_on_last_chance_resolved)


func load_menu() -> void:
	RoundManager.last_chance_resolved.disconnect_all() if RoundManager.last_chance_resolved.get_connections().size() > 0 else null
	_load_scene("res://scenes/menus/main_menu.tscn")


# ---------------------------------------------------------------------------
# Spawning graczy i botów
# ---------------------------------------------------------------------------

func _spawn_players() -> void:
	var hud    := get_active_hud()
	var humans : int = GameManager.num_human_players
	var idx    : int = 0

	for i in range(humans):
		var p := PLAYER_SCENE.instantiate() as CharacterBody2D
		p.player_id       = i + 1
		p.is_bot          = false
		p.global_position = _arena.spawn_pixel(idx)
		idx += 1
		_players_root.add_child(p)
		_players.append(p)
		_connect_player(p, hud)

	for i in range(GameManager.num_bots):
		var bot := PLAYER_SCENE.instantiate() as CharacterBody2D
		bot.player_id       = humans + i + 1
		bot.is_bot          = true
		bot.global_position = _arena.spawn_pixel(idx)
		idx += 1
		_players_root.add_child(bot)
		_players.append(bot)
		bot.died.connect(_on_player_died)


func _connect_player(player: CharacterBody2D, hud: CanvasLayer) -> void:
	player.died.connect(_on_player_died)
	if not hud:
		return
	hud.update_lives(player.player_id, player.lives, player.DEFAULT_LIVES)
	player.lives_changed.connect(
		func(pid: int, left: int): hud.update_lives(pid, left, player.DEFAULT_LIVES)
	)


# ---------------------------------------------------------------------------
# Koniec rundy
# ---------------------------------------------------------------------------

func _on_player_died(_pid: int) -> void:
	get_tree().process_frame.connect(_deferred_check_round, CONNECT_ONE_SHOT)


func _deferred_check_round() -> void:
	if not RoundManager._round_active:
		return
	var alive: Array = []
	for p in _players:
		if is_instance_valid(p) and p.is_alive:
			alive.append(p)
	match alive.size():
		0: RoundManager.end_round(-1)
		1: RoundManager.end_round(alive[0].player_id)
		_: pass


func _on_last_chance_resolved(dead_player_id: int, respawned: bool) -> void:
	for p in _players:
		if is_instance_valid(p) and p.player_id == dead_player_id:
			p.resolve_last_chance(respawned)
			return


# ---------------------------------------------------------------------------
# Widoczność HUDów
# ---------------------------------------------------------------------------

func _update_huds(state: GameManager.GameState) -> void:
	var playing : bool = state == GameManager.GameState.PLAYING
	var two_p   : bool = GameManager.num_human_players >= 2
	hud_1p.visible = playing and not two_p
	hud_2p.visible = playing and two_p


func _on_state_changed(_old: GameManager.GameState, new_state: GameManager.GameState) -> void:
	_update_huds(new_state)


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func get_active_hud() -> CanvasLayer:
	if hud_1p.visible: return hud_1p
	if hud_2p.visible: return hud_2p
	return null
