extends Control

@onready var start_1p: Button = $VBox/Start1P
@onready var start_2p: Button = $VBox/Start2P
@onready var quit_button: Button = $VBox/Quit

func _ready() -> void:
	start_1p.pressed.connect(_on_start_1p)
	start_2p.pressed.connect(_on_start_2p)
	quit_button.pressed.connect(_on_quit)

func _on_start_1p() -> void:
	GameManager.start_game(1, 1)

func _on_start_2p() -> void:
	GameManager.start_game(2, 0)

func _on_quit() -> void:
	get_tree().quit()
