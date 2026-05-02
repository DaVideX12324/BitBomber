extends Node

## Persistentny root całej gry.
##
## Architektura Opcja A:
##   Game
##   ├─ HUD1P / HUD2P
##   ├─ Players (Node2D)   ← stały kontener, gracze niszczeni/tworzeni przy każdej grze
##   └─ CurrentMap (Node)  ← podmieniana scena mapy/pokoju
##
## WAŻNE: _spawn_players() wywoływany w load_arena(), NIE w _ready(),
## bo num_human_players/num_bots są ustawiane przez GameManager.start_game()
## PRZED wywołaniem load_arena().

const PLAYER_SCENE = preload("res://scenes/players/player.tscn")

@onready var hud_1p      : CanvasLayer = $HUD1P
@onready var hud_2p      : CanvasLayer = $HUD2P
@onready var players_root: Node2D      = $Players

var _current_map : Node  = null
var _players     : Array = []


func _ready() -> void:
	GameManager.game_node = self
	GameManager.state_changed.connect(_on_state_changed)
	_load_menu()


# ---------------------------------------------------------------------------
# Ładowanie scen
# ---------------------------------------------------------------------------

func _load_map(path: String) -> void:
	if _current_map:
		_current_map.queue_free()
		_current_map = null
	var scene : Node2D = load(path).instantiate() as Node2D
	_current_map = scene
	add_child(_current_map)
	move_child(_current_map, 0)
	_teleport_players()


func _load_menu() -> void:
	_set_players_visible(false)
	if _current_map:
		_current_map.queue_free()
		_current_map = null
	var menu : Node = load("res://scenes/menus/main_menu.tscn").instantiate()
	_current_map = menu
	add_child(menu)
	move_child(menu, 0)


## Wczytaj arenę trybu vs — gracze spawnowani tutaj (już po ustawieniu num_human_players)
func load_arena() -> void:
	_clear_players()              # usuń poprzednich graczy
	_spawn_players()              # stwórz nowych z aktualnymi ustawieniami
	_load_map("res://scenes/maps/arena.tscn")
	_set_players_visible(true)
	_connect_players_to_hud()
	RoundManager.start_round()
	if not RoundManager.last_chance_resolved.is_connected(_on_last_chance_resolved):
		RoundManager.last_chance_resolved.connect(_on_last_chance_resolved)


func load_room(path: String) -> void:
	_load_map(path)
	_set_players_visible(true)


func load_menu() -> void:
	if RoundManager.last_chance_resolved.is_connected(_on_last_chance_resolved):
		RoundManager.last_chance_resolved.disconnect(_on_last_chance_resolved)
	_load_menu()


# ---------------------------------------------------------------------------
# Gracze
# ---------------------------------------------------------------------------

func _spawn_players() -> void:
	var humans : int = GameManager.num_human_players
	for i in range(humans):
		var p := PLAYER_SCENE.instantiate() as CharacterBody2D
		p.player_id = i + 1
		p.is_bot    = false
		players_root.add_child(p)
		_players.append(p)
		p.died.connect(_on_player_died)

	for i in range(GameManager.num_bots):
		var bot := PLAYER_SCENE.instantiate() as CharacterBody2D
		bot.player_id    = humans + i + 1
		bot.is_bot       = true
		bot.bot_difficulty = GameManager.bot_difficulty  # <-- przekazuj trudność
		players_root.add_child(bot)
		_players.append(bot)
		bot.died.connect(_on_player_died)


## Usuwa wszystkich obecnych graczy (przed nową grą)
func _clear_players() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.queue_free()
	_players.clear()


func _teleport_players() -> void:
	if not _current_map or not _current_map.has_method("spawn_pixel"):
		return
	for i in range(_players.size()):
		var p = _players[i]
		if is_instance_valid(p):
			p.teleport_to(_current_map.spawn_pixel(i))


func _set_players_visible(v: bool) -> void:
	for p in _players:
		if is_instance_valid(p):
			p.visible = v


func _connect_players_to_hud() -> void:
	var hud := get_active_hud()
	if not hud:
		return
	for p in _players:
		if is_instance_valid(p) and not p.is_bot:
			hud.update_lives(p.player_id, p.lives, p.DEFAULT_LIVES)
			p.lives_changed.connect(
					func(pid: int, left: int): hud.update_lives(pid, left, p.DEFAULT_LIVES))


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
# HUD
# ---------------------------------------------------------------------------

func _update_huds(state: GameManager.GameState) -> void:
	var playing : bool = state == GameManager.GameState.PLAYING
	var two_p   : bool = GameManager.num_human_players >= 2
	hud_1p.visible = playing and not two_p
	hud_2p.visible = playing and two_p


func _on_state_changed(_old: GameManager.GameState, new_state: GameManager.GameState) -> void:
	_update_huds(new_state)


func get_active_hud() -> CanvasLayer:
	if hud_1p.visible: return hud_1p
	if hud_2p.visible: return hud_2p
	return null
