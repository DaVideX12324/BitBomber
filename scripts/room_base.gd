extends Node2D

## RoomBase — bazowy skrypt dla każdego pokoju w adventure mode.
##
## Użycie:
##   extends RoomBase  (zamiast extends Node2D)
##
## Każda scena pokoju powinna:
##   1. Rozszerzać RoomBase (lub mieć ten skrypt)
##   2. Ustawiać spawn_points oraz next_room w Inspektorze
##   3. Emitować room_cleared gdy wszyscy wrogowie zginią

## Punkty spawnu graczy w współrzędnych kafelkowych.
## Jeśli puste, game.gd użyje domyślnych SPAWN_POINTS z arena.gd.
@export var spawn_points : Array[Vector2i] = []

## Ścieżka do następnego pokoju (np. "res://scenes/maps/rooms/room_02.tscn").
## Pusta = koniec gry / boss room.
@export var next_room    : String = ""

## Czy to pokój z bossem?
@export var boss_room    : bool   = false

## Rozmiar kafelka — musi być spójny z arenas/player
const GRID_SIZE : int = 64

signal room_cleared


## Zwraca pixel-center n-tego spawna.
## Wywoływane przez game.gd po załadowaniu pokoju.
func spawn_pixel(idx: int) -> Vector2:
	if spawn_points.is_empty():
		## Fallback — róg (1,1)
		return Vector2(GRID_SIZE * 1 + GRID_SIZE / 2, GRID_SIZE * 1 + GRID_SIZE / 2)
	var sp : Vector2i = spawn_points[idx % spawn_points.size()]
	return Vector2(sp.x * GRID_SIZE + GRID_SIZE / 2, sp.y * GRID_SIZE + GRID_SIZE / 2)


## Przejście do następnego pokoju.
## Możesz wywołać ręcznie lub podłączyć do sygnalu room_cleared.
func go_to_next_room() -> void:
	if next_room.is_empty():
		push_warning("RoomBase: next_room nie jest ustawiony!")
		return
	GameManager.game_node.load_room(next_room)


## Override w pokoju jeśli chcesz wykrywać koniec walki.
## Pomyśl: po zabiciu ostatniego wroga wywołaj room_cleared.emit()
func _on_all_enemies_dead() -> void:
	room_cleared.emit()
