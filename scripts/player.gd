extends CharacterBody2D

## Gracz BitBomber — snap-ruch na gridzie 64px, kładzenie bomb, system żyć.
##
## collision_layer = 2  (warstwa graczy — widziana przez eksplozję mask=3)
## collision_mask  = 1  (warstwa mapy — żeby gracz kolidował ze ścianami)

@export var player_id : int  = 1
@export var is_bot    : bool = false

const GRID_SIZE : int   = 64
const MOVE_SPEED: float = 5.0

const BOMB_SCENE = preload("res://scenes/objects/bomb.tscn")

const DEFAULT_LIVES    : int   = 3
const DEFAULT_BOMBS    : int   = 1
const DEFAULT_RANGE    : int   = 2
const DEFAULT_SPEED    : float = 1.0

var lives            : int   = DEFAULT_LIVES
var max_bombs        : int   = DEFAULT_BOMBS
var bomb_range       : int   = DEFAULT_RANGE
var speed_multiplier : float = DEFAULT_SPEED
var _active_bombs    : int   = 0

var has_remote_detonator : bool = false
var has_bomb_pierce      : bool = false

var _grid_pos      : Vector2i = Vector2i.ZERO
var _pixel_target  : Vector2  = Vector2.ZERO
var _moving        : bool     = false
var _move_progress : float    = 0.0
var _move_from     : Vector2  = Vector2.ZERO

var is_alive           : bool = true
var _pending_elim      : bool = false
var _frozen            : bool = false
var _invincible        : bool = false

## Instancja AI — tworzona w _ready() jeśli is_bot == true
var _ai : RefCounted = null

signal died(player_id: int)
signal lives_changed(player_id: int, lives_left: int)
signal bomb_placed(grid_pos: Vector2i, player_ref: Node)

@onready var _sprite   : Sprite2D  = $Sprite2D
@onready var _fallback : ColorRect = $Fallback

const FALLBACK_COLORS : Dictionary = {
	1: Color(0.2, 0.6, 1.0),
	2: Color(1.0, 0.4, 0.2),
	3: Color(0.2, 0.9, 0.3),
	4: Color(0.9, 0.2, 0.9),
}


func _ready() -> void:
	collision_layer = 2
	collision_mask  = 1
	_fallback.color = FALLBACK_COLORS.get(player_id, Color.WHITE)
	SpriteLoader.apply_or_fallback(_sprite, _fallback, "players/player_%d.png" % player_id)
	_grid_pos     = _pixel_to_grid(global_position)
	_pixel_target = _grid_to_pixel(_grid_pos)
	global_position = _pixel_target

	if is_bot:
		# AI inicjalizowana z opóźnieniem — żeby arena zdążyła się zbudować
		await get_tree().process_frame
		_init_ai()


func _init_ai() -> void:
	var arena := _find_arena()
	if arena == null:
		return
	var BotAI := load("res://scripts/bot_ai.gd")
	_ai = BotAI.new()
	_ai.setup(self, arena)


func _find_arena() -> Node:
	var gn := GameManager.game_node
	if gn and is_instance_valid(gn.get("_current_map")):
		return gn._current_map
	return null


func _process(delta: float) -> void:
	if not is_alive or _frozen:
		return
	if GameManager.is_in_quiz():
		return

	if _moving:
		_move_progress += delta * MOVE_SPEED * speed_multiplier
		if _move_progress >= 1.0:
			_move_progress = 1.0
			_moving = false
		global_position = _move_from.lerp(_pixel_target, _move_progress)
		if is_bot and _ai != null:
			_ai.think(delta)
		return

	if is_bot:
		if _ai != null:
			_ai.think(delta)
		return

	_handle_movement(delta)
	_handle_bomb_input()


# ---------------------------------------------------------------------------
# Teleport
# ---------------------------------------------------------------------------

func teleport_to(px: Vector2) -> void:
	global_position = px
	_grid_pos       = _pixel_to_grid(px)
	_pixel_target   = _grid_to_pixel(_grid_pos)
	_moving         = false
	_move_progress  = 0.0
	_frozen         = false
	_invincible     = false
	modulate.a      = 1.0
	is_alive        = true
	_pending_elim   = false
	visible         = true


func reset_for_new_game() -> void:
	lives            = DEFAULT_LIVES
	max_bombs        = DEFAULT_BOMBS
	bomb_range       = DEFAULT_RANGE
	speed_multiplier = DEFAULT_SPEED
	_active_bombs    = 0
	has_remote_detonator = false
	has_bomb_pierce      = false
	teleport_to(global_position)


# ---------------------------------------------------------------------------
# Ruch snap (tylko gracze ludzcy)
# ---------------------------------------------------------------------------

func _handle_movement(delta: float) -> void:
	if _moving:
		_move_progress += delta * MOVE_SPEED * speed_multiplier
		if _move_progress >= 1.0:
			_move_progress = 1.0
			_moving = false
		global_position = _move_from.lerp(_pixel_target, _move_progress)
		return

	var prefix := "p%d_" % player_id
	var dir := Vector2i.ZERO
	if   Input.is_action_pressed(prefix + "up"):    dir = Vector2i(0, -1)
	elif Input.is_action_pressed(prefix + "down"):  dir = Vector2i(0,  1)
	elif Input.is_action_pressed(prefix + "left"):  dir = Vector2i(-1, 0)
	elif Input.is_action_pressed(prefix + "right"): dir = Vector2i(1,  0)

	if dir == Vector2i.ZERO:
		return

	var target_grid := _grid_pos + dir
	var collision   := move_and_collide(_grid_to_pixel(target_grid) - global_position, true)
	if collision:
		return

	_grid_pos      = target_grid
	_move_from     = global_position
	_pixel_target  = _grid_to_pixel(target_grid)
	_move_progress = 0.0
	_moving        = true


# ---------------------------------------------------------------------------
# Bomby
# ---------------------------------------------------------------------------

func _handle_bomb_input() -> void:
	if Input.is_action_just_pressed("p%d_bomb" % player_id):
		_place_bomb()


func _place_bomb() -> void:
	if _active_bombs >= max_bombs:
		return
	var bomb := BOMB_SCENE.instantiate()
	bomb.global_position  = _grid_to_pixel(_grid_pos)
	bomb.explosion_range  = bomb_range
	bomb.owner_player     = self
	bomb.exploded.connect(_on_bomb_exploded)
	var map_root := _get_map_root()
	map_root.add_child(bomb)
	_active_bombs += 1
	bomb_placed.emit(_grid_pos, self)


func _on_bomb_exploded() -> void:
	_active_bombs = max(_active_bombs - 1, 0)


func _get_map_root() -> Node:
	var gn := GameManager.game_node
	if gn and gn.get("_current_map") != null:
		return gn._current_map
	return get_parent()


# ---------------------------------------------------------------------------
# Obrażenia / system żyć
# ---------------------------------------------------------------------------

func take_hit() -> void:
	if not is_alive or _invincible:
		return
	lives -= 1
	lives_changed.emit(player_id, lives)
	if lives <= 0:
		is_alive      = true
		_pending_elim = true
		if is_bot:
			_eliminate()
		else:
			get_tree().process_frame.connect(_deferred_last_chance, CONNECT_ONE_SHOT)
	else:
		_start_hit_sequence()


func _deferred_last_chance() -> void:
	if _pending_elim:
		RoundManager.trigger_last_chance(player_id)


func resolve_last_chance(respawned: bool) -> void:
	_pending_elim = false
	if respawned:
		lives = 1
		lives_changed.emit(player_id, lives)
		_respawn()
	else:
		_eliminate()


func _start_hit_sequence() -> void:
	_frozen     = true
	_invincible = true
	_blink(3.0, 0.3)
	await get_tree().create_timer(4.0).timeout
	_frozen = false
	_blink(2.0, 0.1)
	await get_tree().create_timer(2.0).timeout
	_invincible = false
	modulate.a  = 1.0


func _respawn() -> void:
	is_alive = true
	global_position = _pixel_target
	_start_iframes(2.0)


func _start_iframes(duration: float) -> void:
	_invincible = true
	_blink(duration, 0.1)
	await get_tree().create_timer(duration).timeout
	_invincible = false
	modulate.a  = 1.0


func _eliminate() -> void:
	is_alive      = false
	_pending_elim = false
	visible       = false
	died.emit(player_id)


# ---------------------------------------------------------------------------
# Power-upy
# ---------------------------------------------------------------------------

func apply_powerup(powerup_type: String) -> void:
	match powerup_type:
		"range_up":         bomb_range       = min(bomb_range + 1, 8)
		"bomb_up":          max_bombs        = min(max_bombs + 1, 4)
		"speed_up":         speed_multiplier = min(speed_multiplier + 0.3, 2.5)
		"range_max":        bomb_range       = 8
		"remote_detonator": has_remote_detonator = true
		"bomb_pierce":      has_bomb_pierce      = true


# ---------------------------------------------------------------------------
# Helpery
# ---------------------------------------------------------------------------

func _grid_to_pixel(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * GRID_SIZE + GRID_SIZE / 2, gp.y * GRID_SIZE + GRID_SIZE / 2)


func _pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


func get_grid_pos() -> Vector2i:
	return _grid_pos


func _blink(duration: float, interval: float) -> void:
	var steps : int = int(duration / (interval * 2))
	var tw := create_tween().set_loops(steps)
	tw.tween_property(self, "modulate:a", 0.2, interval)
	tw.tween_property(self, "modulate:a", 1.0, interval)
