class_name BbInput
extends RefCounted

## Sterowanie BitBombera: domyślne klawisze akcji, zmiana klawiszy i zapis w user://.
## W hoście klawisze zmienia i zapisuje host — tu tylko dopisujemy brakujące akcje.
## Samodzielnie: SettingsManager przy starcie wczytuje zapisane klawisze, a Opcje → Sterowanie je zmieniają.

const SAVE_PATH := "user://bitbomber_controls.cfg"
const SECTION := "keys"

## Akcja -> domyślne klawisze (fizyczne, niezależne od układu klawiatury).
const DEFAULTS := {
	"p1_up": [KEY_W], "p1_down": [KEY_S], "p1_left": [KEY_A], "p1_right": [KEY_D],
	"p1_bomb": [KEY_SPACE],
	"quiz_p1_a": [KEY_1], "quiz_p1_b": [KEY_2], "quiz_p1_c": [KEY_3], "quiz_p1_d": [KEY_4],
	"p2_up": [KEY_UP], "p2_down": [KEY_DOWN], "p2_left": [KEY_LEFT], "p2_right": [KEY_RIGHT],
	"p2_bomb": [KEY_ENTER, KEY_KP_0],
	"quiz_p2_a": [KEY_KP_1, KEY_7], "quiz_p2_b": [KEY_KP_2, KEY_8],
	"quiz_p2_c": [KEY_KP_3, KEY_9], "quiz_p2_d": [KEY_KP_4, KEY_0],
	"pause": [KEY_ESCAPE],
}

## Krótkie nazwy klawiszy w grze (reszta z OS.get_keycode_string, „Kp ” → „Num ”).
const KEY_NAMES := {
	"Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
	"Space": "Spacja", "Escape": "Esc", "Kp Enter": "Num Enter",
}


## Dodaje brakujące akcje i domyślne klawisze, których akcja nie ma (project.godot nie ma np. „pause”
## ani zapasowych 7–0 gracza 2). Zapisane przez gracza klawisze wczytuje potem load_saved().
static func ensure_actions() -> void:
	for action: String in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var keys := keys_of(action)
		for key in DEFAULTS[action]:
			if not keys.has(key):
				_add_key(action, key)


## Wczytuje klawisze zapisane w Opcjach (tylko gra samodzielna).
static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for action: String in DEFAULTS:
		var saved: Variant = cfg.get_value(SECTION, action, null)
		if saved is Array and not (saved as Array).is_empty():
			_set_keys(action, saved)


static func save() -> void:
	var cfg := ConfigFile.new()
	for action: String in DEFAULTS:
		cfg.set_value(SECTION, action, keys_of(action))
	cfg.save(SAVE_PATH)


## Przypisuje akcji jeden klawisz. Jeśli miała go inna akcja, ta dostaje dotychczasowe klawisze tej
## (zamiana miejscami), żeby żadna akcja nie została bez klawisza ani dwie nie miały tego samego.
static func rebind(action: String, physical_key: Key) -> void:
	var old_keys := keys_of(action)
	for other: String in DEFAULTS:
		if other == action:
			continue
		var other_keys := keys_of(other)
		if not other_keys.has(physical_key):
			continue
		other_keys.erase(physical_key)
		for key in old_keys:
			if not other_keys.has(key) and not _is_used_elsewhere(key, action, other):
				other_keys.append(key)
		_set_keys(other, other_keys)
	_set_keys(action, [physical_key])


static func reset_defaults() -> void:
	for action: String in DEFAULTS:
		_set_keys(action, DEFAULTS[action])


## Klawisze fizyczne akcji (zdarzenia z samym keycode przeliczane na fizyczne).
static func keys_of(action: String) -> Array:
	var keys: Array = []
	for ev in _key_events(action):
		var code: Key = ev.physical_keycode
		if code == KEY_NONE:
			code = ev.keycode   # zdarzenie z samym keycode: kody liter i cyfr są te same co fizyczne (układ US)
		if code != KEY_NONE and not keys.has(code):
			keys.append(code)
	return keys


## Nazwy klawiszy akcji wg aktualnego układu klawiatury, np. „W”, „Num 1/7”, „Enter/Num 0”.
static func key_label(action: String, separator: String = "/") -> String:
	var names: PackedStringArray = []
	for ev in _key_events(action):
		var code: Key = ev.keycode
		if code == KEY_NONE and _is_keypad(ev.physical_keycode):
			code = ev.physical_keycode   # Windows bez NumLocka zamienia Num 1 na End, Num 0 na Insert…
		elif code == KEY_NONE:
			code = DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
		var name := key_name(code)
		if not names.has(name):
			names.append(name)
	return separator.join(names) if not names.is_empty() else "?"


static func key_name(code: Key) -> String:
	var name := OS.get_keycode_string(code)
	return KEY_NAMES.get(name, name.replace("Kp ", "Num "))


static func _is_keypad(code: Key) -> bool:
	return code == KEY_KP_ENTER or (code >= KEY_KP_MULTIPLY and code <= KEY_KP_9)


static func _key_events(action: String) -> Array:
	var events: Array = []
	if not InputMap.has_action(action):
		return events
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			events.append(ev)
	return events


## Zastępuje klawisze akcji (zdarzenia pada i myszy zostają).
static func _set_keys(action: String, physical_keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in _key_events(action):
		InputMap.action_erase_event(action, ev)
	for key in physical_keys:
		_add_key(action, int(key))


static func _add_key(action: String, physical_key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_key
	InputMap.action_add_event(action, ev)


static func _is_used_elsewhere(key: Key, skip_a: String, skip_b: String) -> bool:
	for action: String in DEFAULTS:
		if action != skip_a and action != skip_b and keys_of(action).has(key):
			return true
	return false
