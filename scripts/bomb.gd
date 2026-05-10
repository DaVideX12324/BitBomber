extends StaticBody2D

const EXPLOSION_SCENE = preload("res://scenes/objects/explosion.tscn")
const GRID_SIZE : int   = 64
const FUSE_TIME : float = 2.0

@export var explosion_range : int  = 1
var owner_player            : Node = null

signal exploded

@onready var _sprite   : Sprite2D  = $Sprite2D
@onready var _fallback : ColorRect = $Fallback

var _timer : float = 0.0

## Shader inline — żółty pierścień od krawędzi do centrum w miarę odliczania
const _FUSE_SHADER_CODE := """
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4  glow_color : source_color = vec4(1.0, 0.85, 0.0, 1.0);

void fragment() {
	// UV (0,0) = lewy górny róg, (1,1) = prawy dolny
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;   // 0 = środek, 1 = narożnik

	// Krawędź zalewania: zaczyna od 1.0 (krawędź) i idzie do 0.0 (środek)
	float fill_edge = 1.0 - progress;

	// Miękkie przejście (szerokość 0.15)
	float t = smoothstep(fill_edge - 0.15, fill_edge + 0.05, dist);

	vec4 original = texture(TEXTURE, UV);

	// Mieszamy oryginalny kolor z glow_color tylko tam gdzie alfa > 0
	vec4 result = mix(original, glow_color * vec4(1.0, 1.0, 1.0, original.a), t * original.a);
	COLOR = result;
}
"""

var _fuse_shader : ShaderMaterial


func _ready() -> void:
	add_to_group("bomb")
	collision_layer = 4
	collision_mask  = 0

	if has_node("/root/SpriteLoader"):
		SpriteLoader.apply_or_fallback(_sprite, _fallback, "objects/bomb.png")

	_fallback.pivot_offset = _fallback.size / 2.0

	# Tworzymy i przypisujemy shader do sprite'a
	var sh := Shader.new()
	sh.code = _FUSE_SHADER_CODE
	_fuse_shader = ShaderMaterial.new()
	_fuse_shader.shader = sh
	_sprite.material = _fuse_shader


func _process(delta: float) -> void:
	_timer += delta
	var progress : float = clampf(_timer / FUSE_TIME, 0.0, 1.0)

	# Pulsowanie skali (oryginalne)
	var scale_val := 1.0 + 0.1 * sin(_timer * TAU * 2.0)
	var new_scale := Vector2(scale_val, scale_val)
	_sprite.scale   = new_scale
	_fallback.scale = new_scale

	# Aktualizacja shadera
	if _fuse_shader:
		_fuse_shader.set_shader_parameter("progress", progress)

	# Fallback (ColorRect) — modulujemy kolor od szarego do żółtego
	_fallback.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.0, 0.85, 0.0, 1.0), progress)

	if _timer >= FUSE_TIME:
		_explode()


## Czas pozostały do wybuchu — używane przez bot_ai.gd do omijania bomb
func time_left() -> float:
	return maxf(FUSE_TIME - _timer, 0.0)


func _explode() -> void:
	set_process(false)
	exploded.emit()

	var arena  : Node     = _get_arena()
	var origin : Vector2i = _pixel_to_grid(global_position)

	_spawn_explosion(global_position)

	var directions : Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir : Vector2i in directions:
		for i : int in range(1, explosion_range):
			var cell : Vector2i = origin + dir * i
			var pos  : Vector2  = _grid_to_pixel(cell)

			if arena and arena.has_method("is_solid") and arena.is_solid(cell):
				break

			if arena and arena.has_method("is_breakable") and arena.is_breakable(cell):
				_spawn_explosion(pos)
				arena.break_cell(cell)
				break

			_spawn_explosion(pos)

	queue_free()


func _spawn_explosion(pos: Vector2) -> void:
	var exp := EXPLOSION_SCENE.instantiate()
	exp.global_position = pos
	var target := _get_map_root()
	if target:
		target.add_child(exp)


func _get_arena() -> Node:
	var node := get_parent() as Node
	while node:
		if node.has_method("is_solid"):
			return node
		node = node.get_parent()
	return null


func _get_map_root() -> Node:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.get("game_node") != null:
		var gn = gm.game_node
		if gn and gn.get("_current_map") != null:
			return gn._current_map
	return get_parent()


func _pixel_to_grid(px: Vector2) -> Vector2i:
	return Vector2i(int(px.x / GRID_SIZE), int(px.y / GRID_SIZE))


func _grid_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID_SIZE + GRID_SIZE / 2.0, cell.y * GRID_SIZE + GRID_SIZE / 2.0)
