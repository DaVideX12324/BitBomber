extends CanvasLayer

## Wspólna logika dla hud_1p i hud_2p.
## Węzły StatsLabel i RoundLabel są pobierane przez ścieżkę
## — działają zarówno w 1P jak i 2P (2P ma dwa StatsLabele).


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)


func update_player(pid: int, bombs: int, bomb_range: int, speed: float) -> void:
	var txt := "Bomby: %d\nZasięg: %d\nPręd: %.1fx" % [bombs, bomb_range, speed]
	var label_path := "Root/PanelLeft/VBox/StatsLabel" if pid == 1 else "Root/PanelRight/VBox/StatsLabel"
	var lbl := get_node_or_null(label_path)
	if lbl:
		lbl.text = txt


func update_round(round_num: int) -> void:
	var lbl := get_node_or_null("Root/RoundPanel/RoundLabel")
	if lbl:
		lbl.text = "Runda %d" % round_num


func show_message(msg: String, duration: float = 2.0) -> void:
	var root := get_node_or_null("Root")
	if not root:
		return
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1, 1, 0.3))
	lbl.layout_mode = 1
	lbl.anchor_left   = 0.5; lbl.anchor_right  = 0.5
	lbl.anchor_top    = 0.5; lbl.anchor_bottom = 0.5
	lbl.offset_left   = -220; lbl.offset_right  = 220
	lbl.offset_top    = -36;  lbl.offset_bottom = 36
	root.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(duration - 0.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	await tw.finished
	lbl.queue_free()


func _on_state_changed(_old, _new) -> void:
	pass  # widoczność kontroluje game.gd
