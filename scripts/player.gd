extends CharacterBody2D

## Gracz BitBomber — snap-ruch na gridzie 64px, kładzenie bomb, system żyć.

@export var player_id: int = 1
@export var is_bot: bool = false

const GRID_SIZE: int = 64
const MOVE_SPEED: float = 5.0

const BOMB_SCENE = preload("res://scenes/objects/bomb.tscn")

# --- Staty gracza ---
var bomb_range: int = 2
var max_bombs: int = 1
var speed_multiplier: float = 1.0
var _active_bombs: int = 0

# --- System żyć ---
const DEFAULT_LIVES: int = 3
var lives: int = DEFAULT_LIVES

# --- Ruch snap ---
var _grid_pos: Vector2i = Vector2i.ZERO
var _pixel_target: Vector2 = Vector2.ZERO
var _moving: bool = false
var _move_progress: float = 0.0
var _move_from: Vector2 = Vector2.ZERO

# --- Stan ---
var is_alive: bool = true
var _pending_elimination: bool = false
var _frozen: bool = false       # freeze po trafieniu
var _invincible: bool = false   # iframes po freeze

signal died(player_id: int)
signal lives_changed(player_id: int, lives_left: int)
signal bomb_placed(grid_pos: Vector2i, player_ref: Node)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _fallback: ColorRect = $Fallback

const FALLBACK_COLORS = {
	1: Color(0.2, 0.6, 1.0),
	2: Color(1.0, 0.4, 0.2),
	3: Color(0.2, 0.9, 0.3),
	4: Color(0.9, 0.2, 0.9),
}


func _ready() -> void:
	_fallback.color = FALLBACK_COLORS.get(player_id, Color.WHITE)
	var sprite_path = "players/player_%d.png" % player_id
	SpriteLoader.apply_or_fallback(_sprite, _fallback, sprite_path)
	_grid_pos = _pixel_to_grid(global_position)
	_pixel_target = _grid_to_pixel(_grid_pos)
	global_position = _pixel_target


func _process(delta: float) -> void:
	if is_bot or not is_alive:
		return
	if GameManager.is_in_quiz():
		return
	if _frozen:
		return
	_handle_movement(delta)
	_handle_bomb_input()


# ---------------------------------------------------------------------------
# Ruch snap
# ---------------------------------------------------------------------------

func _handle_movement(delta: float) -> void:
	if _moving:
		_move_progress += delta * MOVE_SPEED * speed_multiplier
		if _move_progress >= 1.0:
			_move_progress = 1.0
			_moving = false
		global_position = _move_from.lerp(_pixel_target, _move_progress)
		return

	var prefix = "p%d_" % player_id
	var dir = Vector2i.ZERO
	if Input.is_action_pressed(prefix + "up"):    dir = Vector2i(0, -1)
	elif Input.is_action_pressed(prefix + "down"): dir = Vector2i(0, 1)
	elif Input.is_action_pressed(prefix + "left"): dir = Vector2i(-1, 0)
	elif Input.is_action_pressed(prefix + "right"): dir = Vector2i(1, 0)

	if dir == Vector2i.ZERO:
		return

	var target_grid = _grid_pos + dir
	var target_pixel = _grid_to_pixel(target_grid)
	var collision = move_and_collide(target_pixel - global_position, true)
	if collision:
		return

	_grid_pos = target_grid
	_move_from = global_position
	_pixel_target = target_pixel
	_move_progress = 0.0
	_moving = true


# ---------------------------------------------------------------------------
# Bomby
# ---------------------------------------------------------------------------

func _handle_bomb_input() -> void:
	var prefix = "p%d_" % player_id
	if Input.is_action_just_pressed(prefix + "bomb"):
		_place_bomb()


func _place_bomb() -> void:
	if _active_bombs >= max_bombs:
		return
	var bomb = BOMB_SCENE.instantiate()
	bomb.global_position = _grid_to_pixel(_grid_pos)
	bomb.explosion_range = bomb_range
	bomb.owner_player = self
	bomb.exploded.connect(_on_bomb_exploded)
	get_parent().add_child(bomb)
	_active_bombs += 1
	bomb_placed.emit(_grid_pos, self)


func _on_bomb_exploded() -> void:
	_active_bombs = max(_active_bombs - 1, 0)


# ---------------------------------------------------------------------------
# Obrażenia / system żyć
# ---------------------------------------------------------------------------

func take_hit() -> void:
	if not is_alive or _invincible:
		return

	lives -= 1
	lives_changed.emit(player_id, lives)

	if lives <= 0:
		# Brak żyć — eliminacja
		is_alive = false
		if is_bot:
			_eliminate()
		else:
			RoundManager.trigger_last_chance(player_id)
			_pending_elimination = true
	else:
		# Zostały życia — freeze + iframes
		_start_hit_sequence()


## Wywoływane przez RoundManager.last_chance_resolved
func resolve_last_chance(respawned: bool) -> void:
	_pending_elimination = false
	if respawned:
		lives = 1  # wraca z 1 życiem
		lives_changed.emit(player_id, lives)
		_respawn()
	else:
		_eliminate()


## Freeze 4s → iframes 2s
func _start_hit_sequence() -> void:
	_frozen = true
	_invincible = true
	_blink(4.0, 0.15)  # szybkie miganie podczas freeze
	await get_tree().create_timer(4.0).timeout
	_frozen = false
	_blink(2.0, 0.1)   # szybsze miganie podczas iframes
	await get_tree().create_timer(2.0).timeout
	_invincible = false
	modulate.a = 1.0


func _respawn() -> void:
	is_alive = true
	global_position = _pixel_target
	_start_iframes(2.0)


func _start_iframes(duration: float) -> void:
	_invincible = true
	_blink(duration, 0.1)
	await get_tree().create_timer(duration).timeout
	_invincible = false
	modulate.a = 1.0


func _eliminate() -> void:
	is_alive = false
	visible = false
	died.emit(player_id)


# ---------------------------------------------------------------------------
# Power-upy
# ---------------------------------------------------------------------------

func apply_powerup(powerup_type: String) -> void:
	match powerup_type:
		"range_up":  bomb_range = min(bomb_range + 1, 8)
		"bomb_up":   max_bombs = min(max_bombs + 1, 4)
		"speed_up":  speed_multiplier = min(speed_multiplier + 0.3, 2.5)
		"range_max": bomb_range = 8


# ---------------------------------------------------------------------------
# Helpery
# ---------------------------------------------------------------------------

func _grid_to_pixel(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * GRID_SIZE + GRID_SIZE / 2, gp.y * GRID_SIZE + GRID_SIZE / 2)


func _pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


func get_grid_pos() -> Vector2i:
	return _grid_pos


## Miganie przez cały czas trwania (nie blokuje — nie używa await)
func _blink(duration: float, interval: float) -> void:
	var steps := int(duration / (interval * 2))
	var tw := create_tween().set_loops(steps)
	tw.tween_property(self, "modulate:a", 0.2, interval)
	tw.tween_property(self, "modulate:a", 1.0, interval)
