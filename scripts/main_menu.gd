extends Control

## Menu główne BitBomber.

func _ready() -> void:
	$Center/Panel/VBox/Btn1P.pressed.connect(_on_1p)
	$Center/Panel/VBox/Btn2P.pressed.connect(_on_2p)
	$Center/Panel/VBox/BtnQuit.pressed.connect(_on_quit)


func _on_1p() -> void:
	GameManager.start_game(1)  # 1 gracz + bot


func _on_2p() -> void:
	GameManager.start_game(2)  # 2 graczy


func _on_quit() -> void:
	get_tree().quit()
