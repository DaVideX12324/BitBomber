extends Node

signal exit_requested

const HOST_SCENE := "res://modules/BitBomber/scenes/game.tscn"
const STANDALONE_SCENE := "res://scenes/game.tscn"

var _host_api = null
var _manifest: Dictionary = {}
var _scene_root: Node
var _current_scene: Node


func _ready() -> void:
	_scene_root = get_node_or_null("SceneRoot")
	if _scene_root == null:
		_scene_root = Node.new()
		_scene_root.name = "SceneRoot"
		add_child(_scene_root)
	_mark_embedded_mode()
	_ensure_input_actions()
	_open_scene(_resolve_game_scene())


func embedded_start(host_api, manifest: Dictionary = {}) -> void:
	_host_api = host_api
	_manifest = manifest.duplicate(true)
	_mark_embedded_mode()


func embedded_stop() -> void:
	get_tree().paused = false


func _resolve_game_scene() -> String:
	if ResourceLoader.exists(HOST_SCENE):
		return HOST_SCENE
	return STANDALONE_SCENE


func _open_scene(scene_path: String) -> void:
	var packed := load(scene_path)
	if not packed is PackedScene:
		push_warning("BitBomber module: cannot load scene %s" % scene_path)
		return

	if _current_scene and is_instance_valid(_current_scene):
		_current_scene.queue_free()

	_current_scene = packed.instantiate()
	_scene_root.add_child(_current_scene)


func _mark_embedded_mode() -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.host_module = self if _host_api != null or ResourceLoader.exists(HOST_SCENE) else null


func request_exit() -> void:
	get_tree().paused = false
	if _host_api and _host_api.has_method("request_exit"):
		_host_api.request_exit()
		return
	exit_requested.emit()


func _ensure_input_actions() -> void:
	_ensure_key_action("p1_up", KEY_W)
	_ensure_key_action("p1_down", KEY_S)
	_ensure_key_action("p1_left", KEY_A)
	_ensure_key_action("p1_right", KEY_D)
	_ensure_key_action("p1_bomb", KEY_SPACE)
	_ensure_key_action("p2_up", KEY_UP)
	_ensure_key_action("p2_down", KEY_DOWN)
	_ensure_key_action("p2_left", KEY_LEFT)
	_ensure_key_action("p2_right", KEY_RIGHT)
	_ensure_key_action("p2_bomb", KEY_ENTER)
	_ensure_key_action("p2_bomb", KEY_KP_0)
	_ensure_key_action("quiz_p1_a", KEY_1)
	_ensure_key_action("quiz_p1_b", KEY_2)
	_ensure_key_action("quiz_p1_c", KEY_3)
	_ensure_key_action("quiz_p1_d", KEY_4)
	_ensure_key_action("quiz_p2_a", KEY_KP_1)
	_ensure_key_action("quiz_p2_b", KEY_KP_2)
	_ensure_key_action("quiz_p2_c", KEY_KP_3)
	_ensure_key_action("quiz_p2_d", KEY_KP_4)
	_ensure_key_action("pause", KEY_ESCAPE)


func _ensure_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and (existing_event as InputEventKey).keycode == keycode:
			return

	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action_name, event)
