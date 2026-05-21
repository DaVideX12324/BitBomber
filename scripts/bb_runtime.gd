extends RefCounted

const HOST_MODULE_ROOT := "res://modules/BitBomber"
const STANDALONE_ROOT := "res://"


static func module_root() -> String:
	if FileAccess.file_exists(HOST_MODULE_ROOT + "/module_manifest.json"):
		return HOST_MODULE_ROOT
	return STANDALONE_ROOT


static func path(local_path: String) -> String:
	var normalized := local_path.trim_prefix("/")
	if module_root() == STANDALONE_ROOT:
		return STANDALONE_ROOT + normalized
	return module_root() + "/" + normalized
