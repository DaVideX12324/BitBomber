extends RefCounted

## Efekty dźwiękowe BitBombera: resources/sounds/<nazwa>.wav (generuje tools/gen_sounds.py).
## W hoście przez AudioService.play_sfx (szyna SFX, głośność z ustawień hosta),
## samodzielnie przez jednorazowy AudioStreamPlayer.

const BBRuntime = preload("bb_runtime.gd")

static var _cache : Dictionary = {}


## pitch_jitter: losowe odchylenie wysokości (np. 0.08 = ±8%), żeby powtarzane dźwięki nie brzmiały identycznie.
static func play(sfx_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.0) -> void:
	var stream := _stream(sfx_name)
	if stream == null:
		return
	var pitch := 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("AudioService")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx(stream, volume_db, pitch)
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	if AudioServer.get_bus_index("SFX") >= 0:
		player.bus = "SFX"
	tree.root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


static func _stream(sfx_name: String) -> AudioStream:
	if not _cache.has(sfx_name):
		var path := BBRuntime.path("resources/sounds/%s.wav" % sfx_name)
		_cache[sfx_name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[sfx_name]
