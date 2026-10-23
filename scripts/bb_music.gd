extends RefCounted

## Muzyka BitBombera: resources/music/<utwór>.wav (generuje tools/gen_music.py, pętla w pliku).
## W hoście przez AudioService (szyna Music, głośność z ustawień hosta),
## samodzielnie przez własny AudioStreamPlayer w korzeniu drzewa.

const BBRuntime = preload("bb_runtime.gd")
const TRACK_PREFIX := "bitbomber_"
const PLAYER_NAME := "BbMusicPlayer"


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
	var player := tree.root.get_node_or_null(PLAYER_NAME) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = PLAYER_NAME
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.volume_db = -6.0
		if AudioServer.get_bus_index("Music") >= 0:
			player.bus = "Music"
		tree.root.add_child(player)
	if player.playing and player.stream and player.stream.resource_path == path:
		return
	player.stream = load(path)
	player.play()
