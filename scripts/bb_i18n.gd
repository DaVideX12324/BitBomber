class_name BbI18n
extends RefCounted

## Tłumaczenia BitBombera: deleguje do I18nService hosta.
## Samodzielnie (bez hosta) czyta własne słowniki JSON z resources/i18n/ — po polsku, z angielskim jako zapasowym.

const BbRuntime = preload("bb_runtime.gd")

const STANDALONE_LANG := "pl"
const FALLBACK_LANG := "en"

static var _registered := false
## Słowniki trybu samodzielnego: język -> {klucz: tekst}. Puste, dopóki nie są potrzebne.
static var _local: Dictionary = {}


static func register() -> void:
	if _registered:
		return
	var svc := _get_service()
	if svc != null:
		var dir_path := BbRuntime.path("resources/i18n/")
		svc.call("register_dir", dir_path)
		_registered = true


static func _get_service() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root:
		return main_loop.root.get_node_or_null("I18nService")
	return null


static func t(key: String, fallback: String = "") -> String:
	register()
	var svc := _get_service()
	if svc != null:
		return str(svc.call("t", key, fallback))
	return _local_t(key, fallback)


static func tf(key: String, args: Dictionary, fallback: String = "") -> String:
	return t(key, fallback).format(args)


static func plural(key_base: String, n: int, args: Dictionary = {}) -> String:
	register()
	var svc := _get_service()
	if svc != null:
		return str(svc.call("plural", key_base, n, args))
	var fmt_args := args.duplicate()
	fmt_args["n"] = n
	var full_key := "%s.%s" % [key_base, _plural_suffix_pl(n)]
	if has(full_key):
		return tf(full_key, fmt_args)
	return tf("%s.many" % key_base, fmt_args)


static func has(key: String) -> bool:
	register()
	var svc := _get_service()
	if svc != null:
		return bool(svc.call("has", key))
	_load_local()
	for lang in _local:
		if (_local[lang] as Dictionary).has(key):
			return true
	return false


static func reload() -> void:
	_registered = false
	_local.clear()
	register()
	var svc := _get_service()
	if svc != null:
		svc.call("reload")


# ---------------------------------------------------------------------------
# Tryb samodzielny
# ---------------------------------------------------------------------------

static func _local_t(key: String, fallback: String) -> String:
	_load_local()
	for lang in [STANDALONE_LANG, FALLBACK_LANG]:
		var dict: Dictionary = _local.get(lang, {})
		if dict.has(key):
			return str(dict[key])
	if fallback != "":
		return fallback
	return key


static func _load_local() -> void:
	if not _local.is_empty():
		return
	for lang in [STANDALONE_LANG, FALLBACK_LANG]:
		var path := BbRuntime.path("resources/i18n/%s.json" % lang)
		var parsed: Variant = null
		if FileAccess.file_exists(path):
			parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_local[lang] = parsed
		else:
			push_warning("BbI18n: brak słownika %s" % path)
			_local[lang] = {}


## Liczba mnoga po polsku: 1 = one, 2–4 (bez 12–14) = few, reszta = many.
static func _plural_suffix_pl(n: int) -> String:
	var abs_n := absi(n)
	if abs_n == 1:
		return "one"
	var mod10 := abs_n % 10
	var mod100 := abs_n % 100
	if mod10 >= 2 and mod10 <= 4 and not (mod100 >= 12 and mod100 <= 14):
		return "few"
	return "many"
