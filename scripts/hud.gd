extends CanvasLayer

## HUD wyświetlający stan graczy i aktualną rundę.

@onready var _p1_label: Label = $Bar/HBox/P1Info/P1Label
@onready var _p2_label: Label = $Bar/HBox/P2Info/P2Label
@onready var _round_label: Label = $Bar/HBox/RoundLabel


func update_player(pid: int, bombs: int, bomb_range: int, speed: float) -> void:
	var txt = "P%d  💣%d  🎯%d  ⚡%.1fx" % [pid, bombs, bomb_range, speed]
	if pid == 1:
		_p1_label.text = txt
	else:
		_p2_label.text = txt


func update_round(round_num: int) -> void:
	_round_label.text = "Runda %d" % round_num


func show_message(msg: String, duration: float = 2.0) -> void:
	# Tymczasowy toast na środku ekranu
	var lbl = Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchors_preset = 8  # center
	lbl.set_anchor_and_offset(SIDE_LEFT, 0.5, -200)
	lbl.set_anchor_and_offset(SIDE_RIGHT, 0.5, 200)
	lbl.set_anchor_and_offset(SIDE_TOP, 0.5, -30)
	lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.5, 30)
	lbl.theme_override_font_sizes = {}
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.modulate = Color(1, 1, 0.3)
	add_child(lbl)
	await get_tree().create_timer(duration).timeout
	lbl.queue_free()
