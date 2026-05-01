extends CanvasLayer

## HUD singleton.
## - Ukryty dopóki GameManager.current_state == MENU
## - 1P: panel tylko po lewej
## - 2P: panel po lewej (P1) i po prawej (P2)
##
## Publiczne API:
##   HUD.update_player(pid, bombs, bomb_range, speed)
##   HUD.update_round(round_num)
##   HUD.show_message(text, duration)

# ---- węzły ----
var _root: Control          # pełnoekranowy anchor
var _panel_left: PanelContainer
var _panel_right: PanelContainer
var _p1_label: Label
var _p2_label: Label
var _round_label: Label


func _ready() -> void:
	layer = 10
	_build_ui()
	# Start ukryty — pokaż dopiero gdy gra się zacznie
	_root.visible = false
	GameManager.state_changed.connect(_on_state_changed)


func _build_ui() -> void:
	# Pełnoekranowy Control jako kontener
	_root = Control.new()
	_root.set_anchor_and_offset(SIDE_LEFT,   0.0, 0)
	_root.set_anchor_and_offset(SIDE_RIGHT,  1.0, 0)
	_root.set_anchor_and_offset(SIDE_TOP,    0.0, 0)
	_root.set_anchor_and_offset(SIDE_BOTTOM, 1.0, 0)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# --- panel LEWY (P1) ---
	_panel_left = _make_panel()
	_panel_left.set_anchor_and_offset(SIDE_LEFT,   0.0,  8)
	_panel_left.set_anchor_and_offset(SIDE_RIGHT,  0.0, 148)
	_panel_left.set_anchor_and_offset(SIDE_TOP,    0.5, -90)
	_panel_left.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  90)
	_root.add_child(_panel_left)

	var vb1 := _make_vbox()
	_panel_left.add_child(vb1)

	_add_player_header(vb1, 1, Color(0.2, 0.6, 1.0))
	_p1_label = _add_stats_label(vb1)

	# --- panel ŚRODKOWY (numer rundy) — góra ekranu ---
	var round_panel := PanelContainer.new()
	round_panel.set_anchor_and_offset(SIDE_LEFT,   0.5, -70)
	round_panel.set_anchor_and_offset(SIDE_RIGHT,  0.5,  70)
	round_panel.set_anchor_and_offset(SIDE_TOP,    0.0,   6)
	round_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  38)
	_root.add_child(round_panel)

	_round_label = Label.new()
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 15)
	round_panel.add_child(_round_label)

	# --- panel PRAWY (P2) — początkowo ukryty ---
	_panel_right = _make_panel()
	_panel_right.set_anchor_and_offset(SIDE_LEFT,   1.0, -148)
	_panel_right.set_anchor_and_offset(SIDE_RIGHT,  1.0,  -8)
	_panel_right.set_anchor_and_offset(SIDE_TOP,    0.5,  -90)
	_panel_right.set_anchor_and_offset(SIDE_BOTTOM, 0.5,   90)
	_panel_right.visible = false
	_root.add_child(_panel_right)

	var vb2 := _make_vbox()
	_panel_right.add_child(vb2)

	_add_player_header(vb2, 2, Color(1.0, 0.4, 0.2))
	_p2_label = _add_stats_label(vb2)

	# init wartości
	update_player(1, 1, 2, 1.0)
	update_player(2, 1, 2, 1.0)
	update_round(1)


# ---------------------------------------------------------------------------
# Helpers budowania UI
# ---------------------------------------------------------------------------

func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _make_vbox() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	return v


func _add_player_header(parent: Control, pid: int, color: Color) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hb)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.color = color
	hb.add_child(dot)

	var lbl := Label.new()
	lbl.text = "Gracz %d" % pid
	lbl.add_theme_font_size_override("font_size", 15)
	hb.add_child(lbl)


func _add_stats_label(parent: Control) -> Label:
	var sep := HSeparator.new()
	parent.add_child(sep)

	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)
	return lbl


# ---------------------------------------------------------------------------
# Publiczne API
# ---------------------------------------------------------------------------

func update_player(pid: int, bombs: int, bomb_range: int, speed: float) -> void:
	var txt := "💣 Bomby: %d\n🎯 Zasięg: %d\n⚡ Pręd: %.1fx" % [bombs, bomb_range, speed]
	if pid == 1:
		_p1_label.text = txt
	else:
		_p2_label.text = txt


func update_round(round_num: int) -> void:
	_round_label.text = "Runda  %d" % round_num


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
	_root.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(duration - 0.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	await tw.finished
	lbl.queue_free()


# ---------------------------------------------------------------------------
# Reakcja na zmianę stanu gry
# ---------------------------------------------------------------------------

func _on_state_changed(_old, new_state) -> void:
	match new_state:
		GameManager.GameState.PLAYING:
			_root.visible = true
			# Prawy panel tylko dla 2P
			_panel_right.visible = GameManager.num_human_players >= 2
		GameManager.GameState.MENU:
			_root.visible = false
		_:
			pass  # QUIZ / ROUND_END / GAME_OVER — HUD zostaje widoczny
