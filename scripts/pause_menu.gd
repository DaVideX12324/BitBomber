extends CanvasLayer

## Menu pauzy — wyświetlane po naciśnięciu ESC podczas rozgrywki.
## Wymaga węzłów w scenie:
##   PauseMenu (CanvasLayer, layer=10)
##   └─ Overlay      (ColorRect, full-rect, color #00000099)
##   └─ Panel        (PanelContainer, anchors center)
##       └─ VBox
##           └─ Icon       (Label)
##           └─ Title      (Label)
##           └─ BtnResume  (Button)
##           └─ BtnMenu    (Button)

@onready var _overlay    : ColorRect      = $Overlay
@onready var _panel      : PanelContainer = $Panel
@onready var _btn_resume : Button         = $Panel/VBox/BtnResume
@onready var _btn_menu   : Button         = $Panel/VBox/BtnMenu

var _paused : bool = false


func _ready() -> void:
	visible = false
	_btn_resume.pressed.connect(resume)
	_btn_menu.pressed.connect(_on_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Nie pauzuj jeśli gra nie jest w trybie PLAYING
		if GameManager.current_state != GameManager.GameState.PLAYING:
			return
		# Nie pauzuj jeśli death_screen jest widoczny
		if _death_screen_visible():
			return
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _paused:
		resume()
	else:
		pause()


func pause() -> void:
	if _paused:
		return
	_paused = true
	get_tree().paused = true
	_show()


func resume() -> void:
	if not _paused:
		return
	_paused = false
	get_tree().paused = false
	_hide()


func _on_menu() -> void:
	_paused = false
	get_tree().paused = false
	visible = false
	GameManager.go_to_menu()


func _death_screen_visible() -> bool:
	var gn := GameManager.game_node
	if not is_instance_valid(gn):
		return false
	var ds := gn.get_node_or_null("DeathScreen")
	if ds and ds.visible:
		return true
	return false


func _show() -> void:
	visible = true
	_overlay.modulate.a = 0.0
	_panel.modulate.a   = 0.0
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.2)


func _hide() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 0.0, 0.15)
	tw.parallel().tween_property(_panel, "modulate:a", 0.0, 0.15)
	await tw.finished
	visible = false
