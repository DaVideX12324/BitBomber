extends CanvasLayer

## HUD singleton — globalny pasek stanu niezależny od areny.
## Dodaj do Autoload jako "HUD" (autoloads/hud.gd).
##
## API:
##   HUD.update_player(pid, bombs, bomb_range, speed)
##   HUD.update_round(round_num)
##   HUD.show_message(text, duration)
##   HUD.set_visible_hud(bool)   -- ukrywa pasek (menu główne)

# ---- węzły UI (tworzone kodem, nie przez .tscn) ----
var _bar: PanelContainer
var _p1_label: Label
var _p2_label: Label
var _round_label: Label


func _ready() -> void:
	layer = 10  # ponad areną, pod quiz overlayem
	_build_ui()


func _build_ui() -> void:
	# ---- pasek górny ----
	_bar = PanelContainer.new()
	_bar.set_anchor_and_offset(SIDE_LEFT,   0.0, 0)
	_bar.set_anchor_and_offset(SIDE_RIGHT,  1.0, 0)
	_bar.set_anchor_and_offset(SIDE_TOP,    0.0, 0)
	_bar.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 48)
	add_child(_bar)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 32)
	_bar.add_child(hbox)

	# P1
	var p1box := HBoxContainer.new()
	p1box.add_theme_constant_override("separation", 8)
	hbox.add_child(p1box)

	var dot1 := ColorRect.new()
	dot1.custom_minimum_size = Vector2(18, 18)
	dot1.color = Color(0.2, 0.6, 1.0)
	p1box.add_child(dot1)

	_p1_label = Label.new()
	_p1_label.add_theme_font_size_override("font_size", 14)
	p1box.add_child(_p1_label)

	# Runda (środek)
	_round_label = Label.new()
	_round_label.add_theme_font_size_override("font_size", 15)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(_round_label)

	# P2
	var p2box := HBoxContainer.new()
	p2box.add_theme_constant_override("separation", 8)
	hbox.add_child(p2box)

	var dot2 := ColorRect.new()
	dot2.custom_minimum_size = Vector2(18, 18)
	dot2.color = Color(1.0, 0.4, 0.2)
	p2box.add_child(dot2)

	_p2_label = Label.new()
	_p2_label.add_theme_font_size_override("font_size", 14)
	p2box.add_child(_p2_label)

	# init tekstu
	update_player(1, 1, 2, 1.0)
	update_player(2, 1, 2, 1.0)
	update_round(1)


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func update_player(pid: int, bombs: int, bomb_range: int, speed: float) -> void:
	var txt := "P%d  💣%d  🎯%d  ⚡%.1fx" % [pid, bombs, bomb_range, speed]
	if pid == 1:
		_p1_label.text = txt
	else:
		_p2_label.text = txt


func update_round(round_num: int) -> void:
	_round_label.text = "Runda %d" % round_num


func set_visible_hud(v: bool) -> void:
	_bar.visible = v


func show_message(msg: String, duration: float = 2.0) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1, 1, 0.3))
	lbl.set_anchor_and_offset(SIDE_LEFT,   0.5, -220)
	lbl.set_anchor_and_offset(SIDE_RIGHT,  0.5,  220)
	lbl.set_anchor_and_offset(SIDE_TOP,    0.5,  -36)
	lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.5,   36)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(duration - 0.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	await tw.finished
	lbl.queue_free()
