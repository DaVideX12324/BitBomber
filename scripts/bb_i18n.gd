class_name BbI18n
extends RefCounted

## Tłumaczenia BitBombera: deleguje do I18nService, a w razie jego braku zwraca fallback.

const BbRuntime = preload("bb_runtime.gd")

static var _registered := false


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
	return fallback if fallback != "" else key


static func tf(key: String, args: Dictionary, fallback: String = "") -> String:
	register()
	var svc := _get_service()
	if svc != null:
		return str(svc.call("tf", key, args, fallback))
	return (fallback if fallback != "" else key).format(args)


static func plural(key_base: String, n: int, args: Dictionary = {}) -> String:
	register()
	var svc := _get_service()
	if svc != null:
		return str(svc.call("plural", key_base, n, args))
	var fmt_args := args.duplicate()
	fmt_args["n"] = n
	return ("%s.many" % key_base).format(fmt_args)


static func has(key: String) -> bool:
	register()
	var svc := _get_service()
	if svc != null:
		return bool(svc.call("has", key))
	return false


static func reload() -> void:
	_registered = false
	register()
	var svc := _get_service()
	if svc != null:
		svc.call("reload")
