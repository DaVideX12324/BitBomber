extends Node

signal exit_requested
## Koniec sesji (wynik jak w ModuleHostApi.finish_session) — dla uruchomienia bez hosta.
signal session_finished(result: Dictionary)

const HOST_SCENE := "res://modules/BitBomber/scenes/game.tscn"
const STANDALONE_SCENE := "res://scenes/game.tscn"

var _host_api = null
var _manifest: Dictionary = {}
var _scene_root: Node
var _current_scene: Node


func _ready() -> void:
	BbI18n.register()
	_scene_root = get_node_or_null("SceneRoot")
	if _scene_root == null:
		_scene_root = Node.new()
		_scene_root.name = "SceneRoot"
		add_child(_scene_root)
	_mark_embedded_mode()
	_ensure_input_actions()
	_open_scene(_resolve_game_scene())


func embedded_start(host_api, manifest: Dictionary = {}) -> void:
	BbI18n.register()
	_host_api = host_api
	_manifest = manifest.duplicate(true)
	_mark_embedded_mode()
	var config: Dictionary = host_api.get_session_config() if host_api and host_api.has_method("get_session_config") else {}
	if not config.is_empty():
		GameManager.start_from_config(config)


## Wywoływane przez grę na koniec sesji.
func report_session(result: Dictionary) -> void:
	if _host_api and _host_api.has_method("finish_session"):
		_host_api.finish_session(result)
	session_finished.emit(result)


func embedded_stop() -> void:
	get_tree().paused = false
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.host_session = false


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
	BbInput.ensure_actions()
