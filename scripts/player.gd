extends CharacterBody2D

const BBRuntime = preload("bb_runtime.gd")
const BbSfx = preload("bb_sfx.gd")

## Gracz BitBomber — snap-ruch na gridzie 64px, kładzenie bomb, system życ.
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

var _bomb_scene: PackedScene = load(BBRuntime.path("scenes/objects/bomb.tscn"))

const DEFAULT_LIVES    : int   = 1
const DEFAULT_BOMBS    : int   = 1
const DEFAULT_RANGE    : int   = 1
const DEFAULT_SPEED    : float = 1.0
## Mnożnik MOVE_SPEED: +SPEED_STEP za power-up, do MAX_SPEED (jak Bomb It: 1,3–2,1 px/kl.).
const SPEED_STEP       : float = 0.15
const MAX_SPEED        : float = 1.75
const MAX_LIVES        : int   = 5
## Tryb KILL: po tylu sekundach odrodzenie na swoim spawnie
const KILL_RESPAWN_DELAY : float = 2.0

var lives            : int   = DEFAULT_LIVES
var max_bombs        : int   = DEFAULT_BOMBS
var bomb_range       : int   = DEFAULT_RANGE
var speed_mult     : float = DEFAULT_SPEED
## Stały mnożnik szybkości postaci (boty: move_speed z profilu AI, np. łatwy 0,92); power-upy mnożą speed_mult
var move_speed_scale : float = 1.0
var _active_bombs    : int   = 0

## Power-upy specjalne (Bomb It: BombShoesProp, ShieldProp, InvincibilityProp)
var has_kick   : bool  = false
var has_shield : bool  = false
var _star_time : float = 0.0
## Nieśmiertelność z gwiazdki trwa tyle sekund
const STAR_DURATION : float = 8.0
## Kara za złą odpowiedź na pytanie-bonus: chód wolniejszy o tyle
const SLOW_FACTOR : float = 0.6
var _slow_time : float = 0.0
## Tryb KILL: sekundy do odrodzenia (0 = żyje albo nie czeka) i czy wrócić z tarczą (quiz odrodzenia)
var _respawn_left   : float = 0.0
var _respawn_shield : bool  = false


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
## Tryb KILL: zginął i zaraz się odrodzi (killer_id 0 = nieznany)
signal killed(player_id: int, killer_id: int)
signal lives_changed(player_id: int, lives_left: int)
signal bomb_placed(grid_pos: Vector2i, player_ref: Node)
signal powerup_collected(player_id: int, powerup_type: String)

@onready var _sprite   : Sprite2D  = $Sprite2D

## Arkusz postaci: kolumny stoi / krok A / krok B, wiersze dół / lewo / prawo / góra
const SHEET_COLS : int = 3
const SHEET_ROWS : int = 4
## Klatki chodu na sekundę przy szybkości 1,0
const WALK_FPS : float = 8.0
var _facing_row : int = 0
var _anim_time  : float = 0.0

func _ready() -> void:
	add_to_group("players")
	# scena ma arkusz gracza 1 (podgląd w edytorze); pozostali gracze — swój arkusz
	if player_id != 1:
		_sprite.texture = load(BBRuntime.path("resources/sprites/players/player_%d.png" % player_id))

	_grid_pos       = _pixel_to_grid(global_position)
	_pixel_target   = _grid_to_pixel(_grid_pos)
	global_position = _pixel_target

	if is_bot:
		call_deferred("_init_ai")


func _init_ai() -> void:
	var arena := _find_arena()
	if arena == null:
		return

	var BotAIScript = load(BBRuntime.path("scripts/bot_ai.gd"))
	var ai_node = Node.new()
	ai_node.set_script(BotAIScript)
	ai_node.name = "BotAI"
	ai_node.bot_node  = self
	ai_node.grid_size = GRID_SIZE
	add_child(ai_node)
	_ai = ai_node


func _find_arena() -> Node:
	var gn := GameManager.game_node
	if gn and is_instance_valid(gn.get("_current_map")):
		return gn._current_map
	return null


func _physics_process(delta: float) -> void:
	if _respawn_left > 0.0:
		_tick_respawn(delta)
		return
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
	_update_walk_anim(delta)
	_grid_pos = _closest_grid_pos()
	if _star_time > 0.0:
		_star_time = maxf(_star_time - delta, 0.0)
		modulate = Color.from_hsv(fmod(_star_time * 1.5, 1.0), 0.5, 1.0) if _star_time > 0.0 else Color.WHITE
	if _slow_time > 0.0:
		_slow_time = maxf(_slow_time - delta, 0.0)
		_sprite.modulate = Color(0.55, 0.7, 1.0) if _slow_time > 0.0 else Color.WHITE
	_check_bomb_exits()


func _check_bomb_exits() -> void:
	for i in range(_bombs_inside.size() - 1, -1, -1):
		var b = _bombs_inside[i]
		if not is_instance_valid(b):
			_bombs_inside.remove_at(i)
			continue
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
	_respawn_left   = 0.0
	visible         = true
	bot_input_direction = Vector2.ZERO


## Wywoływane przez game.gd na początku każdej nowej rundy.
## Gracze NIE są usuwani — tylko resetujemy statsy, życia i stan.
func reset_for_new_round() -> void:
	# Statsy
	lives          = DEFAULT_LIVES
	max_bombs      = DEFAULT_BOMBS
	bomb_range     = DEFAULT_RANGE
	speed_mult     = DEFAULT_SPEED
	_active_bombs  = 0
	has_kick       = false
	has_shield     = false
	_star_time     = 0.0
	_slow_time     = 0.0
	_respawn_left  = 0.0
	_sprite.modulate = Color.WHITE
	# Czyśzczenie bomb, na których się stoi
	_bombs_inside.clear()
	# Reset flag stanu
	is_alive      = true
	_pending_elim = false
	_frozen       = false
	_invincible   = false
	modulate.a    = 1.0
	visible       = true
	velocity      = Vector2.ZERO
	bot_input_direction = Vector2.ZERO
	bot_wants_to_bomb   = false
	# Reinicjalizacja AI bota — kasujemy stary węzeł i tworzymy nowy
	# (AI trzyma referencję do areny, która jest przebudowywana co rundę)
	if is_bot and is_instance_valid(_ai):
		_ai.queue_free()
		_ai = null
		call_deferred("_init_ai")
	# Teleport nastąpi pó́żniej przez game.gd → _teleport_players()
	# (mapa musi już istnieć, żeby spawn_pixel() zwrócił prawidłową pozycję)


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
		velocity = direction * MOVE_SPEED * speed_mult * move_speed_scale * (SLOW_FACTOR if _slow_time > 0.0 else 1.0)
		move_and_slide()
		if has_kick:
			_try_kick(direction)

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


func _update_walk_anim(delta: float) -> void:
	if _sprite.hframes != SHEET_COLS:
		return
	var v := velocity
	if v.length_squared() < 1.0:
		_anim_time = 0.0
		_sprite.frame = _facing_row * SHEET_COLS
		return
	if absf(v.x) > absf(v.y):
		_facing_row = 1 if v.x < 0 else 2
	else:
		_facing_row = 3 if v.y < 0 else 0
	_anim_time += delta * WALK_FPS * speed_mult
	var col : int = [1, 0, 2, 0][int(_anim_time) % 4]
	_sprite.frame = _facing_row * SHEET_COLS + col


## Wejście w bombę z kopnięciem — bomba sunie w kierunku ruchu.
func _try_kick(direction: Vector2) -> void:
	var dir := Vector2i(roundi(direction.x), roundi(direction.y))
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body and body.is_in_group("bomb") and body.has_method("kick") \
				and Vector2i(-col.get_normal().round()) == dir:
			if body.kick(dir):
				BbSfx.play("kick", -4.0, 0.08)


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

	for b in get_tree().get_nodes_in_group("bomb"):
		if Vector2i(int(b.global_position.x / GRID_SIZE), int(b.global_position.y / GRID_SIZE)) == bomb_cell:
			return

	var map_root := _get_map_root()
	var bomb := _bomb_scene.instantiate()
	bomb.global_position = _grid_to_pixel(bomb_cell)
	bomb.explosion_range = bomb_range
	bomb.owner_player    = self
	bomb.add_to_group("bomb")

	for p in get_tree().get_nodes_in_group("players"):
		if p.global_position.distance_to(bomb.global_position) < (GRID_SIZE * 0.75):
			bomb.add_collision_exception_with(p)
			p.add_collision_exception_with(bomb)
			p._bombs_inside.append(bomb)

	bomb.exploded.connect(_on_bomb_exploded)
	map_root.add_child(bomb)
	_active_bombs += 1
	BbSfx.play("bomb_place", -6.0, 0.06)
	bomb_placed.emit(bomb_cell, self)


func _on_bomb_exploded() -> void:
	_active_bombs = max(_active_bombs - 1, 0)


func _get_map_root() -> Node:
	var gn := GameManager.game_node
	if gn and gn.get("_current_map") != null:
		return gn._current_map
	return get_parent()


func take_hit(attacker_id: int = 0) -> void:
	if not is_alive or _invincible or _star_time > 0.0:
		return
	if has_shield:
		# Tarcza zjada jedno trafienie, potem chwila nieśmiertelności na wyjście z ognia.
		has_shield = false
		BbSfx.play("shield_break", -4.0)
		powerup_collected.emit(player_id, "shield_lost")
		_start_iframes(1.0)
		return
	# Natychmiastowe ustawienie invincible — blokuje kolejne eksplozje
	# trafiające gracza w tym samym lub następnym framie (multi-bomb insta-kill).
	_invincible = true
	lives -= 1
	lives_changed.emit(player_id, lives)
	if lives <= 0:
		is_alive      = false
		BbSfx.play("death", -3.0, 0.05)
		if GameManager.is_kill_mode():
			_die_and_respawn(attacker_id)
			return
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


func is_awaiting_last_chance() -> bool:
	return _pending_elim


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
	_blink(3.0, 0.3)
	await get_tree().create_timer(2.0).timeout
	_frozen = false
	_blink(2.0, 0.1)
	await get_tree().create_timer(2.0).timeout
	_invincible = false
	modulate.a  = 1.0


func _respawn() -> void:
	is_alive = true
	var arena := _find_arena()
	if arena and arena.has_method("nearest_free_cell"):
		# Spawn mógł zostać zasypany w nagłej śmierci.
		_pixel_target = _grid_to_pixel(arena.nearest_free_cell(_pixel_to_grid(_pixel_target)))
	global_position = _pixel_target
	_start_iframes(2.0)


## Tryb KILL: znika, po KILL_RESPAWN_DELAY wraca na swój spawn z pełnym życiem i chwilą nieśmiertelności.
## Power-upy zostają (jak w Bomb It). Quiz odrodzenia (field_quiz.gd) zmienia czas przez set_respawn_in.
func _die_and_respawn(killer_id: int) -> void:
	_spawn_death_fx()
	visible  = false
	velocity = Vector2.ZERO
	_respawn_left   = KILL_RESPAWN_DELAY
	_respawn_shield = false
	killed.emit(player_id, killer_id)


## Tryb KILL, w trakcie czekania: odrodzenie za `seconds` (shield = wraca z tarczą).
func set_respawn_in(seconds: float, shield: bool = false) -> void:
	if is_alive or _respawn_left <= 0.0:
		return
	_respawn_left   = maxf(seconds, 0.01)
	_respawn_shield = shield


func is_respawning() -> bool:
	return not is_alive and _respawn_left > 0.0


func respawn_time_left() -> float:
	return _respawn_left


func _tick_respawn(delta: float) -> void:
	_respawn_left -= delta
	if _respawn_left > 0.0:
		return
	_respawn_left = 0.0
	if is_alive or not RoundManager._round_active:
		return
	lives = DEFAULT_LIVES
	lives_changed.emit(player_id, lives)
	visible = true
	_respawn()
	if _respawn_shield:
		has_shield = true
		powerup_collected.emit(player_id, "shield")


## Kara za złą odpowiedź na pytanie-bonus.
func apply_slow(duration: float) -> void:
	_slow_time = maxf(_slow_time, duration)


## Kopia postaci na mapie: spłaszcza się, obraca i znika na czerwono (gracz w tym czasie już niewidoczny).
func _spawn_death_fx() -> void:
	var map_root := _get_map_root()
	if map_root == null or not _sprite.visible or _sprite.texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = _sprite.texture
	ghost.hframes = _sprite.hframes
	ghost.vframes = _sprite.vframes
	ghost.frame   = _sprite.frame
	ghost.z_index = 2
	map_root.add_child(ghost)
	ghost.global_position = global_position
	var tw := ghost.create_tween().set_parallel()
	tw.tween_property(ghost, "scale", Vector2(1.5, 0.3), 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(ghost, "rotation", 0.5, 0.4)
	tw.tween_property(ghost, "modulate", Color(1.0, 0.3, 0.3, 0.0), 0.45)
	tw.chain().tween_callback(ghost.queue_free)


## Nagła śmierć: spadający blok zabija od razu — bez nieśmiertelności i ostatniej szansy.
func crush() -> void:
	if not is_alive:
		return
	lives = 0
	lives_changed.emit(player_id, lives)
	BbSfx.play("death", -3.0, 0.05)
	_eliminate()


func _start_iframes(duration: float) -> void:
	_invincible = true
	_blink(duration, 0.1)
	await get_tree().create_timer(duration).timeout
	_invincible = false
	modulate.a  = 1.0


func _eliminate() -> void:
	is_alive      = false
	_pending_elim = false
	if visible:
		_spawn_death_fx()
	visible       = false
	died.emit(player_id)


func apply_powerup(type: String) -> void:
	match type:
		"range_up":  bomb_range    = min(bomb_range + 1, 7)
		"bomb_up":   max_bombs     = min(max_bombs + 1, 4)
		"speed_up":  speed_mult     = minf(speed_mult + SPEED_STEP, MAX_SPEED)
		"life_up":   lives          = min(lives + 1, MAX_LIVES)
		"kick":      has_kick       = true
		"shield":    has_shield     = true
		"star":      _star_time     = STAR_DURATION
		"quiz":      pass   # pytanie-bonus — obsługuje field_quiz.gd (sygnał powerup_collected)
	BbSfx.play("pickup", -6.0, 0.03)
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
