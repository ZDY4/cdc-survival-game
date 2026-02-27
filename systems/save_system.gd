extends Node
# SaveSystem - 存档系统（支持Web和桌面平台）

const SAVE_DIR: String = "user://saves/"
const SAVE_FILE: String = "savegame.json"
const LOCAL_STORAGE_KEY: String = "cdc_survival_save"

var _is_web: bool = false

func _ready():
	_is_web = OS.has_feature("web")
	
	if not _is_web:
		# 桌面平台：创建保存目"		if not DirAccess.dir_exists_absolute(SAVE_DIR):
			DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	else:
		# Web平台：初始化JavaScriptBridge
		_init_web_storage()

func _init_web_storage():
	# 检查JavaScriptBridge是否可用
	if Engine.has_singleton("JavaScriptBridge"):
		print("JavaScriptBridge available for Web storage")

func _is_web_platform() -> bool:
	return OS.has_feature("web") or OS.has_feature("wasm") or OS.has_feature("javascript")

func _save_to_local_storage(save_data: Dictionary) -> bool:
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	
	var js_bridge = Engine.get_singleton("JavaScriptBridge")
	var json_string = JSON.stringify(save_data)
	
	# 使用JavaScript localStorage
	var js_code = "localStorage.setItem('%s', '%s');" % [LOCAL_STORAGE_KEY, json_string.replace("'", "\\'")]
	js_bridge.eval(js_code)
	return true

func _load_from_local_storage() -> Dictionary:
	if not Engine.has_singleton("JavaScriptBridge"):
		return {}
	
	var js_bridge = Engine.get_singleton("JavaScriptBridge")
	
	# 从localStorage读取
	var js_code = "localStorage.getItem('%s') || '{}';" % LOCAL_STORAGE_KEY
	var result = js_bridge.eval(js_code)
	
	if result == null or result == "{}" or result == "":
		return {}
	
	var json = JSON.new()
	if json.parse(str(result)) != OK:
		return {}
	
	return json.get_data()

func _has_local_storage_save() -> bool:
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	
	var js_bridge = Engine.get_singleton("JavaScriptBridge")
	var js_code = "!!localStorage.getItem('%s');" % LOCAL_STORAGE_KEY
	var result = js_bridge.eval(js_code)
	return result == true

func _delete_local_storage_save() -> bool:
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	
	var js_bridge = Engine.get_singleton("JavaScriptBridge")
	var js_code = "localStorage.removeItem('%s');" % LOCAL_STORAGE_KEY
	js_bridge.eval(js_code)
	return true

func save_game():
	var gs = get_node("/root/GameState")
	if not gs:
		return false
	
	var save_data = {
		"player": {
			"hp": gs.player_hp,
			"max_hp": gs.player_max_hp,
			"hunger": gs.player_hunger,
			"thirst": gs.player_thirst,
			"stamina": gs.player_stamina,
			"mental": gs.player_mental,
			"position": gs.player_position
		},
		"inventory": {
			"items": gs.inventory_items.duplicate(),
			"max_slots": gs.inventory_max_slots
		},
		"world": {
			"time": gs.world_time,
			"day": gs.world_day,
			"weather": gs.world_weather,
			"unlocked_locations": gs.world_unlocked_locations.duplicate()
		},
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var success = false
	
	if _is_web_platform():
		# Web平台：使用localStorage
		success = _save_to_local_storage(save_data)
	else:
		# 桌面平台：使用文件系统
		var file = FileAccess.open(SAVE_DIR + SAVE_FILE, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(save_data, "\t"))
			file.close()
			success = true
	
	if success:
		EventBus.emit(EventBus.EventType.GAME_SAVED, {})
	
	return success

func load_game():
	var gs = get_node("/root/GameState")
	if not gs:
		return false
	
	var data = {}
	
	if _is_web_platform():
		# Web平台：从localStorage读取
		data = _load_from_local_storage()
	else:
		# 桌面平台：从文件读取
		var save_path = SAVE_DIR + SAVE_FILE
		if not FileAccess.file_exists(save_path):
			return false
		
		var file = FileAccess.open(save_path, FileAccess.READ)
		if not file:
			return false
		
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) != OK:
			return false
		
		data = json.get_data()
	
	if data.is_empty():
		return false
	
	# 恢复玩家数据
	if data.has("player"):
		var p = data.player
		gs.player_hp = p.get("hp", 100)
		gs.player_max_hp = p.get("max_hp", 100)
		gs.player_hunger = p.get("hunger", 100)
		gs.player_thirst = p.get("thirst", 100)
		gs.player_stamina = p.get("stamina", 100)
		gs.player_mental = p.get("mental", 100)
		gs.player_position = p.get("position", "safehouse")
	
	# 恢复背包
	if data.has("inventory"):
		var inv = data.inventory
		gs.inventory_items.clear()
		var loaded_items = inv.get("items", [])
		for item in loaded_items:
			gs.inventory_items.append(item)
		gs.inventory_max_slots = inv.get("max_slots", 20)
	
	# 恢复世界状"	if data.has("world"):
		var w = data.world
		gs.world_time = w.get("time", 8)
		gs.world_day = w.get("day", 1)
		gs.world_weather = w.get("weather", "clear")
		gs.world_unlocked_locations.clear()
		var loaded_locations = w.get("unlocked_locations", ["safehouse"])
		for location in loaded_locations:
			gs.world_unlocked_locations.append(location)
	
	EventBus.emit(EventBus.EventType.GAME_LOADED, {})
	return true

func has_save():
	if _is_web_platform():
		return _has_local_storage_save()
	else:
		return FileAccess.file_exists(SAVE_DIR + SAVE_FILE)

func delete_save():
	if _is_web_platform():
		return _delete_local_storage_save()
	else:
		if FileAccess.file_exists(SAVE_DIR + SAVE_FILE):
			return DirAccess.remove_absolute(SAVE_DIR + SAVE_FILE) == OK
		return false

# 获取保存数据摘要（用于显示存档信息）
func get_save_info() -> Dictionary:
	var data = {}
	
	if _is_web_platform():
		data = _load_from_local_storage()
	else:
		var save_path = SAVE_DIR + SAVE_FILE
		if not FileAccess.file_exists(save_path):
			return {}
		
		var file = FileAccess.open(save_path, FileAccess.READ)
		if not file:
			return {}
		
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) != OK:
			return {}
		
		data = json.get_data()
	
	if data.is_empty():
		return {}
	
	var info = {
		"exists": true,
		"timestamp": data.get("timestamp", 0)
	}
	
	if data.has("player"):
		info["hp"] = data.player.get("hp", 100)
		info["day"] = data.player.get("position", "safehouse")
	
	if data.has("world"):
		info["day"] = data.world.get("day", 1)
		info["time"] = data.world.get("time", 8)
	
	return info

