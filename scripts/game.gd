extends Node

## Persistentny root całej gry.
## Zarządza podmianą aktywnej subsceny (menu / arena / ...)
## oraz widocznością HUDów.

@onready var hud_1p : CanvasLayer = $HUD1P
@onready var hud_2p : CanvasLayer = $HUD2P

var _current_scene: Node = null


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
	_current_scene = load(path).instantiate()
	add_child(_current_scene)
	move_child(_current_scene, 0)


func load_arena() -> void:
	_load_scene("res://scenes/maps/arena.tscn")


func load_menu() -> void:
	_load_scene("res://scenes/menus/main_menu.tscn")


# ---------------------------------------------------------------------------
# Widoczność HUDów
# ---------------------------------------------------------------------------

func _update_huds(state: GameManager.GameState) -> void:
	var playing: bool = state == GameManager.GameState.PLAYING
	var two_p: bool   = GameManager.num_human_players >= 2
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
