extends Node
# SaveSystem - 存档系统（支持Web和桌面平台）

const SAVE_DIR: String = "user://saves/"
const SAVE_FILE: String = "savegame.json"
const SAVE_FILE_PREFIX: String = "save_"
const SAVE_FILE_EXT: String = ".json"
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

func _save_to_file(path: String, save_data: Dictionary) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	return true

func _load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}
	
	var data = json.get_data()
	return data if data is Dictionary else {}

func _is_valid_save_filename(file_name: String) -> bool:
	if not file_name.ends_with(SAVE_FILE_EXT):
		return false
	return file_name == SAVE_FILE or file_name.begins_with(SAVE_FILE_PREFIX)

func _build_timestamped_save_name() -> String:
	return "%s%d%s" % [SAVE_FILE_PREFIX, Time.get_unix_time_from_system(), SAVE_FILE_EXT]

func _get_desktop_latest_save_path() -> String:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return ""
	
	var dir = DirAccess.open(SAVE_DIR)
	if not dir:
		return ""
	
	var latest_path := ""
	var latest_modified := -1
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and _is_valid_save_filename(file_name):
			var full_path = SAVE_DIR + file_name
			var modified = FileAccess.get_modified_time(full_path)
			if modified > latest_modified:
				latest_modified = modified
				latest_path = full_path
		file_name = dir.get_next()
	dir.list_dir_end()
	
	return latest_path

func save_game():
	var gs = get_node("/root/GameState")
	if not gs:
		return false
	var equip_system = gs.get_equipment_system()
	var equip_data: Dictionary = equip_system.get_save_data() if equip_system else gs.get_pending_equipment_save_data()
	
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
		"equipment": equip_data,
		"world": {
			"time": gs.world_time,
			"day": gs.world_day,
			"weather": gs.world_weather,
			"unlocked_locations": gs.world_unlocked_locations.duplicate(),
			"fog_of_war_by_map": gs.fog_of_war_by_map.duplicate(true)
		},
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var success = false
	
	if _is_web_platform():
		# Web平台：使用localStorage
		success = _save_to_local_storage(save_data)
	else:
		# 桌面平台：写入最新存档 + 时间戳快照
		var latest_path = SAVE_DIR + SAVE_FILE
		var snapshot_path = SAVE_DIR + _build_timestamped_save_name()
		var latest_ok = _save_to_file(latest_path, save_data)
		var snapshot_ok = _save_to_file(snapshot_path, save_data)
		success = latest_ok or snapshot_ok
	
	if success:
		EventBus.emit(EventBus.EventType.GAME_SAVED, {})
	
	return success

func load_game(path: String = ""):
	var gs = get_node("/root/GameState")
	if not gs:
		return false
	
	var data = {}
	
	if _is_web_platform():
		# Web平台：从localStorage读取
		data = _load_from_local_storage()
	else:
		# 桌面平台：默认读取最近一次存档
		var save_path = path
		if save_path.is_empty():
			save_path = _get_desktop_latest_save_path()
		if save_path.is_empty():
			return false
		data = _load_from_file(save_path)
	
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

	# 恢复装备
	if data.has("equipment"):
		var equip_system = gs.get_equipment_system()
		if equip_system:
			equip_system.load_save_data(data.equipment)
		else:
			gs.set_pending_equipment_save_data(data.equipment)
	
	# 恢复世界状"	if data.has("world"):
		var w = data.world
		gs.world_time = w.get("time", 8)
		gs.world_day = w.get("day", 1)
		gs.world_weather = w.get("weather", "clear")
		gs.world_unlocked_locations.clear()
		var loaded_locations = w.get("unlocked_locations", ["safehouse"])
		for location in loaded_locations:
			gs.world_unlocked_locations.append(location)
		gs.fog_of_war_by_map = w.get("fog_of_war_by_map", {})
	
	EventBus.emit(EventBus.EventType.GAME_LOADED, {})
	return true

func load_latest_game() -> bool:
	return load_game()

func has_save():
	if _is_web_platform():
		return _has_local_storage_save()
	else:
		return not _get_desktop_latest_save_path().is_empty()

func delete_save():
	if _is_web_platform():
		return _delete_local_storage_save()
	else:
		if not DirAccess.dir_exists_absolute(SAVE_DIR):
			return false
		
		var dir = DirAccess.open(SAVE_DIR)
		if not dir:
			return false
		
		var removed_count := 0
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and _is_valid_save_filename(file_name):
				if DirAccess.remove_absolute(SAVE_DIR + file_name) == OK:
					removed_count += 1
			file_name = dir.get_next()
		dir.list_dir_end()
		
		return removed_count > 0

# 获取保存数据摘要（用于显示存档信息）
func get_save_info() -> Dictionary:
	var data = {}
	
	if _is_web_platform():
		data = _load_from_local_storage()
	else:
		var save_path = _get_desktop_latest_save_path()
		if save_path.is_empty():
			return {}
		data = _load_from_file(save_path)
	
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

