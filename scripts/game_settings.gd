extends Node

# Przełącznik logów
@export var enable_global_debug: bool = true:
	set(value):
		enable_global_debug = value
		GameManager.debug_enabled = value
		print("Debug logi: ", "WŁĄCZONE" if value else "WYŁĄCZONE")
