extends Node2D

const PLAYER_SCENE = preload("res://scenes/players/player.tscn")

@onready var players_root: Node2D = $Players
@onready var p1_spawn: Marker2D = $P1Spawn
@onready var p2_spawn: Marker2D = $P2Spawn

func _ready() -> void:
	_spawn_players()
	RoundManager.start_round()
	RoundManager.last_chance_resolved.connect(_on_last_chance_resolved)

func _spawn_players() -> void:
	var p1 = PLAYER_SCENE.instantiate()
	p1.player_id = 1
	p1.is_bot = false
	p1.global_position = p1_spawn.global_position
	players_root.add_child(p1)

	if GameManager.num_human_players >= 2:
		var p2 = PLAYER_SCENE.instantiate()
		p2.player_id = 2
		p2.is_bot = false
		p2.global_position = p2_spawn.global_position
		players_root.add_child(p2)
	else:
		var bot = PLAYER_SCENE.instantiate()
		bot.player_id = 2
		bot.is_bot = true
		bot.global_position = p2_spawn.global_position
		players_root.add_child(bot)

func _on_last_chance_resolved(dead_player_id: int, respawned: bool) -> void:
	for child in players_root.get_children():
		if child.player_id == dead_player_id:
			child.resolve_last_chance(respawned)
