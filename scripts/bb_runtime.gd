extends RefCounted

const HOST_MODULE_ROOT := "res://modules/BitBomber"
const STANDALONE_ROOT := "res://"


static func module_root() -> String:
	if ResourceLoader.exists(HOST_MODULE_ROOT + "/README.md"):
		return HOST_MODULE_ROOT
	return STANDALONE_ROOT


static func path(local_path: String) -> String:
	var normalized := local_path.trim_prefix("/")
	if module_root() == STANDALONE_ROOT:
		return STANDALONE_ROOT + normalized
	return module_root() + "/" + normalized
