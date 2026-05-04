extends CharacterBody2D

## Gracz BitBomber — snap-ruch na gridzie 64px, kładzenie bomb, system żyć.
##
## collision_layer = 2  (warstwa graczy)
## collision_mask  = 5  (Mapa + Bomby)

@export var player_id : int  = 1
@export var is_bot    : bool = false
@export var corner_assist_tolerance : float = 24.0

var bot_difficulty : int = 1

const GRID_SIZE  : int   = 64
const MOVE_SPEED : float = 250
const CORNER_SLIDE_SPEED : float = 150.0

const BOMB_SCENE = preload("res://scenes/objects/bomb.tscn")

const DEFAULT_LIVES    : int   = 1
const DEFAULT_BOMBS    : int   = 1
const DEFAULT_RANGE    : int   = 2
const DEFAULT_SPEED    : float = 1.0
const MAX_LIVES        : int   = 5

var lives            : int   = DEFAULT_LIVES
var max_bombs        : int   = DEFAULT_BOMBS
var bomb_range       : int   = DEFAULT_RANGE
var speed_addition : float = DEFAULT_SPEED
var _active_bombs    : int   = 0

var has_remote_detonator : bool = false
var has_bomb_pierce      : bool = false

# --- ZMIENNE DLA AI ---
var bot_input_direction := Vector2.ZERO
var bot_wants_to_bomb   := false

var _grid_pos      : Vector2i = Vector2i.ZERO
var _pixel_target  : Vector2  = Vector2.ZERO

var is_alive      : bool = true
var _pending_elim : bool = false
var _frozen       : bool = false
var _invincible   : bool = false

var _ai : Node = null
var _bombs_inside : Array[Node] = []

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
	add_to_group("players")
	_fallback.color = FALLBACK_COLORS.get(player_id, Color.WHITE)
	
	if has_node("/root/SpriteLoader"):
		SpriteLoader.apply_or_fallback(_sprite, _fallback, "players/player_%d.png" % player_id)
		
	_grid_pos       = _pixel_to_grid(global_position)
	_pixel_target   = _grid_to_pixel(_grid_pos)
	global_position = _pixel_target

	if is_bot:
		call_deferred("_init_ai")

func _init_ai() -> void:
	var arena := _find_arena()
	if arena == null:
		return
		
	var BotAIScript = load("res://scripts/bot_ai.gd") 
	var ai_node = Node.new()
	ai_node.set_script(BotAIScript)
	ai_node.name = "BotAI"
	
	ai_node.bot_node = self
	ai_node.grid_size = GRID_SIZE
	
	add_child(ai_node)
	_ai = ai_node

func _find_arena() -> Node:
	var gn := GameManager.game_node
	if gn and is_instance_valid(gn.get("_current_map")):
		return gn._current_map
	return null

func _physics_process(delta: float) -> void:
	if not is_alive or _frozen:
		return
	if GameManager.is_in_quiz():
		return

	var raw_dir := Vector2.ZERO

	if not is_bot:
		var prefix := "p%d_" % player_id
		raw_dir = Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")
		if Input.is_action_just_pressed(prefix + "bomb"):
			_place_bomb()
	else:
		raw_dir = bot_input_direction
		if bot_wants_to_bomb:
			_place_bomb()
			bot_wants_to_bomb = false

	_handle_movement(delta, raw_dir)
	_grid_pos = _closest_grid_pos()
	
	# Sprawdzanie czy zeszliśmy ze swoich bomb
	_check_bomb_exits()

func _check_bomb_exits() -> void:
	for i in range(_bombs_inside.size() - 1, -1, -1):
		var b = _bombs_inside[i]
		if not is_instance_valid(b):
			_bombs_inside.remove_at(i)
			continue
		
		# Zmniejszony dystans! 
		# Gdy gracz wyjdzie nieco ponad połowę kratki (32px + margines),
		# kolizja zostaje przywrócona. Jeśli minimalnie haczy o bombę, 
		# silnik łagodnie wypchnie go do końca i zamknie "drzwi" za nim.
		if global_position.distance_to(b.global_position) > 42.0:
			remove_collision_exception_with(b)
			b.remove_collision_exception_with(self)
			_bombs_inside.remove_at(i)

func _closest_grid_pos() -> Vector2i:
	var half : int = GRID_SIZE / 2
	return Vector2i(
		int(roundi((global_position.x - half) / GRID_SIZE)),
		int(roundi((global_position.y - half) / GRID_SIZE)))

func teleport_to(px: Vector2) -> void:
	global_position = px
	_grid_pos       = _pixel_to_grid(px)
	_pixel_target   = _grid_to_pixel(_grid_pos)
	_frozen         = false
	_invincible     = false
	modulate.a      = 1.0
	is_alive        = true
	_pending_elim   = false
	visible         = true
	bot_input_direction = Vector2.ZERO

func reset_for_new_game() -> void:
	lives            = DEFAULT_LIVES
	max_bombs        = DEFAULT_BOMBS
	bomb_range       = DEFAULT_RANGE
	speed_addition = DEFAULT_SPEED
	_active_bombs    = 0
	has_remote_detonator = false
	has_bomb_pierce      = false
	teleport_to(global_position)

func _handle_movement(delta: float, raw_dir: Vector2) -> void:
	var direction = raw_dir

	if raw_dir != Vector2.ZERO:
		if raw_dir.x != 0 and raw_dir.y != 0:
			var test_dist = 4.0
			var test_x = test_move(global_transform, Vector2(sign(raw_dir.x) * test_dist, 0))
			var test_y = test_move(global_transform, Vector2(0, sign(raw_dir.y) * test_dist))

			if test_y and not test_x:
				direction.y = 0
			elif test_x and not test_y:
				direction.x = 0
			else:
				if abs(raw_dir.x) > abs(raw_dir.y):
					direction.y = 0
				else:
					direction.x = 0
		else:
			if abs(direction.x) > abs(direction.y):
				direction.y = 0
			else:
				direction.x = 0
		
		direction = direction.normalized()
		velocity = direction * (MOVE_SPEED + speed_addition)
		move_and_slide()

		if get_slide_collision_count() > 0:
			var collision = get_slide_collision(0)
			var normal = collision.get_normal()

			if direction.x != 0 and abs(normal.x) > 0.1:
				_apply_corner_assist("y", direction, delta)
			elif direction.y != 0 and abs(normal.y) > 0.1:
				_apply_corner_assist("x", direction, delta)
	else:
		velocity = Vector2.ZERO
		move_and_slide()

func _apply_corner_assist(axis: String, direction: Vector2, delta: float) -> void:
	var current_pos = global_position.y if axis == "y" else global_position.x
	var offset = fposmod(current_pos, GRID_SIZE)
	var center_dist = offset - (GRID_SIZE / 2.0)
	
	if abs(center_dist) > 1.0 and abs(center_dist) <= corner_assist_tolerance:
		var test_trans = global_transform
		if axis == "y":
			test_trans.origin.y -= center_dist
		else:
			test_trans.origin.x -= center_dist
			
		if not test_move(test_trans, direction * 4.0):
			var slide_amount = sign(center_dist) * CORNER_SLIDE_SPEED * delta
			if abs(slide_amount) > abs(center_dist):
				slide_amount = center_dist
			if axis == "y":
				global_position.y -= slide_amount
			else:
				global_position.x -= slide_amount

func _place_bomb() -> void:
	if _active_bombs >= max_bombs:
		return

	var bomb_cell : Vector2i = _closest_grid_pos()

	# Nie pozwól postawić bomby, jeśli na tym polu już jakaś jest
	for b in get_tree().get_nodes_in_group("bomb"):
		if Vector2i(int(b.global_position.x / GRID_SIZE), int(b.global_position.y / GRID_SIZE)) == bomb_cell:
			return

	var map_root := _get_map_root()
	var bomb := BOMB_SCENE.instantiate()
	bomb.global_position = _grid_to_pixel(bomb_cell)
	bomb.explosion_range = bomb_range
	bomb.owner_player    = self
	bomb.add_to_group("bomb")
	
	# POPRAWA: Dodajemy wyjątek dla KAŻDEGO gracza (w tym bota),
	# który jest blisko środka bomby w momencie jej postawienia.
	# Zapobiega to brutalnemu wypychaniu.
	for p in get_tree().get_nodes_in_group("players"):
		if p.global_position.distance_to(bomb.global_position) < (GRID_SIZE * 0.75):
			bomb.add_collision_exception_with(p)
			p.add_collision_exception_with(bomb)
			p._bombs_inside.append(bomb)
	
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

func take_hit() -> void:
	if not is_alive or _invincible:
		return
	lives -= 1
	lives_changed.emit(player_id, lives)
	if lives <= 0:
		is_alive      = false
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
	await get_tree().create_timer(2.0).timeout
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

func apply_powerup(type: String) -> void:
	match type:
		"range_up":  bomb_range       = min(bomb_range + 1, 8)
		"bomb_up":   max_bombs        = min(max_bombs + 1, 4)
		"speed_up":  speed_addition = min(speed_addition + 50, 500)
		"life_up":   lives            = min(lives + 1, MAX_LIVES)
	if type == "life_up":
		lives_changed.emit(player_id, lives)
	powerup_collected.emit(player_id, type)

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
