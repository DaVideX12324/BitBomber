extends RefCounted

## Muzyka BitBombera: resources/music/<utwór>.wav (generuje tools/gen_music.py, pętla w pliku).
## W hoście przez AudioService (szyna Music, głośność z ustawień hosta),
## samodzielnie przez własny AudioStreamPlayer w korzeniu drzewa.

const BBRuntime = preload("bb_runtime.gd")
const TRACK_PREFIX := "bitbomber_"
const PLAYER_NAME := "BbMusicPlayer"

static var _player: AudioStreamPlayer


static func play(track: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var path := BBRuntime.path("resources/music/%s.wav" % track)
	if not ResourceLoader.exists(path):
		return
	var audio := tree.root.get_node_or_null("AudioService")
	if audio and audio.has_method("register_music_track"):
		audio.register_music_track(TRACK_PREFIX + track, path)
		audio.play_music(TRACK_PREFIX + track)
		return
	if not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = PLAYER_NAME
		_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_player.volume_db = -6.0
		if AudioServer.get_bus_index("Music") >= 0:
			_player.bus = "Music"
		# Pierwsze play() bywa w _ready sceny startowej, gdy korzeń jeszcze dodaje dzieci —
		# dodanie odroczone, a autoplay startuje utwór po wejściu do drzewa.
		_player.autoplay = true
		tree.root.add_child.call_deferred(_player)
	if _player.stream and _player.stream.resource_path == path and (_player.playing or not _player.is_inside_tree()):
		return
	_player.stream = load(path)
	if _player.is_inside_tree():
		_player.play()
