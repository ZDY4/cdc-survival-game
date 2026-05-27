extends RefCounted


func save_snapshot(_slot_id: String, _snapshot: Dictionary) -> bool:
	# 存档格式会在 runtime snapshot 端口完成后落地。
	return false


func load_snapshot(_slot_id: String) -> Dictionary:
	return {}
