extends CharacterBody2D

## Gracz BitBomber — snap-ruch na gridzie 64px, kładzenie bomb, system żyć.
##
## collision_layer = 2  (warstwa graczy)
## collision_mask  = 1  (tylko warstwa mapy — bomby nie blokują gracza fizycznie)

@export var player_id : int  = 1
@export var is_bot    : bool = false

## Maksymalne odchylenie od środka wolnej kratki (w pikselach), przy którym gracz zostanie
## ześlizgnięty. Jeśli grid to 64px, to 32px oznacza krawędź. Im mniejsza wartość,
## tym gracz musi dokładniej celować w wolne przejście.
@export var corner_assist_tolerance : float = 24.0

## Trudność AI — ustawialna z zewnątrz przed add_child().
## 0 = Easy, 1 = Medium, 2 = Hard (odpowiada BotAI.Difficulty)
var bot_difficulty : int = 1

const GRID_SIZE  : int   = 64
const MOVE_SPEED : float = 250
const CORNER_SLIDE_SPEED : float = 150.0

const BOMB_SCENE = preload("res://scenes/objects/bomb.tscn")

const DEFAULT_LIVES    : int   = 3
const DEFAULT_BOMBS    : int   = 1
const DEFAULT_RANGE    : int   = 2
const DEFAULT_SPEED    : float = 1.0
const MAX_LIVES        : int   = 5

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

var is_alive      : bool = true
var _pending_elim : bool = false
var _frozen       : bool = false
var _invincible   : bool = false

var _ai : RefCounted = null

signal died(player_id: int)
signal lives_changed(player_id: int, lives_left: int)
signal bomb_placed(grid_pos: Vector2i, player_ref: Node)
signal powerup_collected(player_id: int, powerup_type: String)

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
	_grid_pos       = _pixel_to_grid(global_position)
	_pixel_target   = _grid_to_pixel(_grid_pos)
	global_position = _pixel_target

	if is_bot:
		await get_tree().process_frame
		_init_ai()

func _init_ai() -> void:
	var arena := _find_arena()
	if arena == null:
		return
	var BotAI := load("res://scripts/bot_ai.gd")
	_ai = BotAI.new()
	_ai.setup(self, arena, bot_difficulty)

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

	if not is_bot:
		_handle_bomb_input()

	if _moving:
		_move_progress += delta * MOVE_SPEED * speed_multiplier
		if _move_progress >= 1.0:
			_move_progress = 1.0
			_moving = false
		global_position = _move_from.lerp(_pixel_target, _move_progress)
		return

	if is_bot:
		if _ai != null:
			_ai.think(delta)
		return

	_handle_movement(delta)

## Tile na którym gracz jest większością ciała.
func _closest_grid_pos() -> Vector2i:
	var half : int = GRID_SIZE / 2
	return Vector2i(
		int(roundi((global_position.x - half) / GRID_SIZE)),
		int(roundi((global_position.y - half) / GRID_SIZE)))

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

# ---------------------------------------------------------------------------
# Ruch snap (tylko gracze ludzcy)
# ---------------------------------------------------------------------------

func _handle_movement(delta: float) -> void:
	var prefix := "p%d_" % player_id
	var raw_dir = Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")
	var direction = raw_dir

	if raw_dir != Vector2.ZERO:
		# --- INTELIGENTNE ROZWIĄZYWANIE RUCHU PO SKOSIE ---
		# Jeśli gracz wciska dwa kierunki naraz (np. Lewo i Dół)
		if raw_dir.x != 0 and raw_dir.y != 0:
			var test_dist = 4.0
			# Wirtualnie sprawdzamy krótki dystans w obu kierunkach
			var test_x = test_move(global_transform, Vector2(sign(raw_dir.x) * test_dist, 0))
			var test_y = test_move(global_transform, Vector2(0, sign(raw_dir.y) * test_dist))

			if test_y and not test_x:
				# Przeszkoda na Y (np. blok na dole), ale X (lewo) jest wolny -> idziemy w X
				direction.y = 0
			elif test_x and not test_y:
				# Przeszkoda na X, ale Y wolny -> idziemy w Y
				direction.x = 0
			else:
				# Obie drogi wolne lub obie zablokowane - standardowe odcięcie
				if abs(raw_dir.x) > abs(raw_dir.y):
					direction.y = 0
				else:
					direction.x = 0
		else:
			# Wciśnięty tylko jeden klawisz, upewniamy się, że odcinamy skosy (na padzie)
			if abs(direction.x) > abs(direction.y):
				direction.y = 0
			else:
				direction.x = 0
		
		direction = direction.normalized()
		velocity = direction * MOVE_SPEED * speed_multiplier
		move_and_slide()

		# --- LOGIKA CORNER ASSIST ---
		if get_slide_collision_count() > 0:
			var collision = get_slide_collision(0)
			var normal = collision.get_normal()

			if direction.x != 0 and abs(normal.x) > 0.1:
				_apply_corner_assist("y", direction, delta)
			elif direction.y != 0 and abs(normal.y) > 0.1:
				_apply_corner_assist("x", direction, delta)
	else:
		# Bardzo ważne - jeśli nic nie wciskamy, całkowicie się zatrzymujemy
		velocity = Vector2.ZERO
		move_and_slide()

func _apply_corner_assist(axis: String, direction: Vector2, delta: float) -> void:
	var current_pos = global_position.y if axis == "y" else global_position.x
	
	# fposmod sprawdza pozycję na kafelku (korzysta z GRID_SIZE = 64)
	var offset = fposmod(current_pos, GRID_SIZE)
	var center_dist = offset - (GRID_SIZE / 2.0)
	
	# Tolerancja: ignorujemy, jeśli gracz jest bardzo blisko środka lub wychylony bardziej niż pozwala corner_assist_tolerance
	if abs(center_dist) > 1.0 and abs(center_dist) <= corner_assist_tolerance:
		
		# Tworzymy testowy punkt (środek kratki, do którego chcemy zsunąć gracza)
		var test_trans = global_transform
		if axis == "y":
			test_trans.origin.y -= center_dist
		else:
			test_trans.origin.x -= center_dist
			
		# Sprawdzamy, czy ze środka gridu można w ogóle iść w pożądanym kierunku
		# Zwróci 'false', jeśli nic tam nie ma (czyli przejście jest wolne).
		if not test_move(test_trans, direction * 4.0):
			var slide_amount = sign(center_dist) * CORNER_SLIDE_SPEED * delta
			
			# Zabezpieczenie przed "przeskakiwaniem" idealnego środka (drganiami)
			if abs(slide_amount) > abs(center_dist):
				slide_amount = center_dist
			
			if axis == "y":
				global_position.y -= slide_amount
			else:
				global_position.x -= slide_amount

# ---------------------------------------------------------------------------
# Bomby
# ---------------------------------------------------------------------------

func _handle_bomb_input() -> void:
	if Input.is_action_just_pressed("p%d_bomb" % player_id):
		_place_bomb()

func _place_bomb() -> void:
	if _active_bombs >= max_bombs:
		return

	var bomb_cell : Vector2i = _closest_grid_pos()

	# Sprawdź czy bomba już leży na tej celli
	for b in get_tree().get_nodes_in_group("bomb"):
		if Vector2i(int(b.global_position.x / GRID_SIZE), int(b.global_position.y / GRID_SIZE)) == bomb_cell:
			return

	var map_root := _get_map_root()
	var bomb := BOMB_SCENE.instantiate()
	bomb.global_position = _grid_to_pixel(bomb_cell)
	bomb.explosion_range = bomb_range
	bomb.owner_player    = self
	bomb.exploded.connect(_on_bomb_exploded)
	map_root.add_child(bomb)
	_active_bombs += 1
	bomb_placed.emit(bomb_cell, self)

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

func apply_powerup(type: String) -> void:
	match type:
		"range_up":  bomb_range       = min(bomb_range + 1, 8)
		"bomb_up":   max_bombs        = min(max_bombs + 1, 4)
		"speed_up":  speed_multiplier = min(speed_multiplier + 0.25, 2.5)
		"life_up":   lives            = min(lives + 1, MAX_LIVES)
	if type == "life_up":
		lives_changed.emit(player_id, lives)
	powerup_collected.emit(player_id, type)

# ---------------------------------------------------------------------------
# Helpery
# ---------------------------------------------------------------------------

func _grid_to_pixel(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * GRID_SIZE + GRID_SIZE / 2, gp.y * GRID_SIZE + GRID_SIZE / 2)

func _pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))

## Używane przez bot_ai — wykonuje jeden krok w danym kierunku.
func _move_grid(dir: Vector2i) -> void:
	if _moving:
		return
	var target_grid : Vector2i = _grid_pos + dir
	var collision := move_and_collide(_grid_to_pixel(target_grid) - global_position, true)
	if collision:
		return
	_grid_pos      = target_grid
	_move_from     = global_position
	_pixel_target  = _grid_to_pixel(target_grid)
	_move_progress = 0.0
	_moving        = true

func get_grid_pos() -> Vector2i:
	return _grid_pos

func _blink(duration: float, interval: float) -> void:
	var steps : int = int(duration / (interval * 2))
	var tw := create_tween().set_loops(steps)
	tw.tween_property(self, "modulate:a", 0.2, interval)
	tw.tween_property(self, "modulate:a", 1.0, interval)
