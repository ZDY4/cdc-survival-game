extends Node
# StoryClueSystem - 环境叙事系统
# 管理碎片化线索、剧情解锁和多周目知识继承
# ===== 信号 =====
signal clue_found(clue_id: String, clue_data: Dictionary)
signal story_chapter_unlocked(chapter_id: String, chapter_title: String)
signal all_clues_found(category: String)
signal new_game_plus_unlocked

# ===== 线索类型 =====
enum ClueType {
	DIARY,      # 日记
	RECORDING,  # 录音
	PHOTO,      # 照片
	MAP,        # 地图
	DOCUMENT,   # 文件
	ITEM        # 特殊物品
}

# ===== 线索数据 =====
const CLUE_DATABASE: Dictionary = {
	# ===== 日记(5) =====
	"diary_doctor_1": {
		"id": "diary_doctor_1",
		"type": "diary",
		"name": "医生日记 #1",
		"title": "第一天",
		"content": "CDC的人今天来了，他们说只是例行检查。但我看到他们在地下停车场卸下了很多密封箱。那些标志...那是生物危险标志",
		"location": "hospital",
		"chapter": "outbreak_beginning",
		"hint": "医院的某个办公桌",
		"unlock_condition": "visit_hospital"
	},
	"diary_nurse_1": {
		"id": "diary_nurse_1",
		"type": "diary",
		"name": "护士日记",
		"title": "混乱的开始",
		"content": "病人开始表现出攻击性。第7病房的王老先生咬伤了值班的李医生。那不是普通的狂犬病，转化太快了...",
		"location": "hospital",
		"chapter": "outbreak_beginning",
		"hint": "护士站的抽屉"
	},
	"diary_survivor_1": {
		"id": "diary_survivor_1",
		"type": "diary",
		"name": "幸存者笔记",
		"title": "第三天",
		"content": "我已经在这个超市里躲了1天。外面的疯子越来越多。我听到广播说军队在市中心设立了撤离点，但怎么去那里？",
		"location": "supermarket",
		"chapter": "survival_struggle",
		"hint": "超市员工休息室的更衣室里"
	},
	"diary_child": {
		"id": "diary_child",
		"type": "diary",
		"name": "小女孩的画册",
		"title": "我的日记",
		"content": "爸爸妈妈变成了怪物。老师说我要躲好。我画了一幅画，藏在床底下。希望有人能找到它...",
		"location": "school",
		"chapter": "innocence_lost",
		"hint": "学校教室的书桌里",
		"has_hidden_item": "drawing_child"
	},
	"diary_soldier": {
		"id": "diary_soldier",
		"type": "diary",
		"name": "士兵日志",
		"title": "撤离失败",
		"content": "命令是清理所有被感染区域。但我们发现有些'感染者'还有意识，他们在求救。我下不了手...所以我逃了",
		"location": "subway",
		"chapter": "military_coverup",
		"hint": "地铁隧道的废弃掩体中"
	},
	
	# ===== 录音(4) =====
	"recording_emergency": {
		"id": "recording_emergency",
		"type": "recording",
		"name": "紧急广播录",
		"title": "最后通告",
		"content": "【录音】这是紧急广播。所有市民请立即前往最近的撤离点。不要相信...【杂音】...他们在撒谎...这不是自然疫情...",
		"location": "street",
		"chapter": "conspiracy",
		"hint": "废弃广播车或收音",
		"playable": true
	},
	"recording_cdc": {
		"id": "recording_cdc",
		"type": "recording",
		"name": "CDC内部通话",
		"title": "项目代号：Phoenix",
		"content": "【录音】博士，病毒样本泄露了。封锁所有出口，启动焚化程序。什么？平民？那不重要，重要的是不能让样本流出。",
		"location": "hospital",
		"chapter": "conspiracy",
		"hint": "医院地下实验室",
		"playable": true
	},
	"recording_mother": {
		"id": "recording_mother",
		"type": "recording",
		"name": "母亲的留言",
		"title": "给儿子的留言",
		"content": "【录音】小明，如果你听到这个，妈妈已经不在了。爸爸变成了那些东西。我在超市的储藏室里放了食物和地图，去找安全屋...",
		"location": "supermarket",
		"chapter": "survival_struggle",
		"hint": "超市收银台的录音",
		"playable": true
	},
	"recording_last_words": {
		"id": "recording_last_words",
		"type": "recording",
		"name": "临终录音",
		"title": "真相",
		"content": "【录音】如果有人找到这个...CDC不是来帮忙的。他们制造了病毒。我在工厂看到他们销毁证据...快跑...不要相信...",
		"location": "factory",
		"chapter": "conspiracy",
		"hint": "工厂办公室的录音设备",
		"playable": true
	},
	
	# ===== 照片(4) =====
	"photo_family": {
		"id": "photo_family",
		"type": "photo",
		"name": "全家福照",
		"title": "幸福时光",
		"content": "一张泛黄的全家福，背面写着'2023年春节，我们永远在一起'。照片中的笑脸现在看来格外刺眼",
		"location": "street",
		"chapter": "innocence_lost",
		"hint": "街道上的废弃车辆"
	},
	"photo_evidence": {
		"id": "photo_evidence",
		"type": "photo",
		"name": "机密照片",
		"title": "实验记录",
		"content": "照片显示了一个地下实验室，穿着防护服的人员正在处理试管。日期戳显示这是在疫情爆发前一周拍摄的",
		"location": "hospital",
		"chapter": "conspiracy",
		"hint": "医院档案室"
	},
	"photo_quarantine": {
		"id": "photo_quarantine",
		"type": "photo",
		"name": "隔离区照",
		"title": "封锁",
		"content": "照片显示城市边缘设置了铁丝网，士兵在巡逻。背面写着'没有撤离，只有封锁'",
		"location": "ruins",
		"chapter": "military_coverup",
		"hint": "废墟中的记者尸体旁"
	},
	"photo_survivors": {
		"id": "photo_survivors",
		"type": "photo",
		"name": "幸存者合影",
		"title": "希望",
		"content": "一群人在安全屋前合影，他们举着'我们还活着'的牌子。这让看到的人感到一丝温暖",
		"location": "safehouse",
		"chapter": "hope",
		"hint": "安全屋的墙上"
	},
	
	# ===== 地图(3) =====
	"map_evacuation": {
		"id": "map_evacuation",
		"type": "map",
		"name": "撤离点地图",
		"title": "官方撤离路线",
		"content": "地图标注了三个撤离点：市中心广场、体育馆、港口。但所有撤离点都被红色叉号标记了，旁边写着'已沦陷'",
		"location": "street",
		"chapter": "survival_struggle",
		"hint": "街道上的公告栏或尸体旁",
		"unlocks_location": "subway"
	},
	"map_underground": {
		"id": "map_underground",
		"type": "map",
		"name": "地铁隧道地图",
		"title": "地下通道",
		"content": "详细的城市地铁系统地图。有手写标注显示某条隧道通往城市外的秘密出口",
		"location": "subway",
		"chapter": "escape_plan",
		"hint": "地铁站控制室",
		"unlocks_location": "forest"
	},
	"map_supply_cache": {
		"id": "map_supply_cache",
		"type": "map",
		"name": "物资藏匿",
		"title": "补给",
		"content": "用红色标记的地图，标注了几个物资藏匿点。其中一个就在附近",
		"location": "supermarket",
		"chapter": "survival_struggle",
		"hint": "超市储藏室",
		"reveals_loot": true
	},
	
	# ===== 文件(4) =====
	"file_cdc_report": {
		"id": "file_cdc_report",
		"type": "document",
		"name": "CDC机密报告",
		"title": "病毒分析报告",
		"content": "【机密】病毒代号X-23，人造基因武器。传播率99%，致死率85%。感染后2小时内出现症状。警告：不存在有效疫苗",
		"location": "hospital",
		"chapter": "conspiracy",
		"hint": "医院地下实验室保险柜"
	},
	"file_news_article": {
		"id": "file_news_article",
		"type": "document",
		"name": "报纸剪报",
		"title": "疫情爆发",
		"content": "'本市出现不明传染病，CDC已介入调查'。日期是疫情爆发前三天。文章角落写着'他们早就知道'",
		"location": "street",
		"chapter": "outbreak_beginning",
		"hint": "街道上的废弃报摊"
	},
	"file_research_notes": {
		"id": "file_research_notes",
		"type": "document",
		"name": "研究笔记",
		"title": "抗体研究",
		"content": "少数个体对病毒表现出天然抗性。他们的血液中可能存在抗体。需要更多样本进行测试",
		"location": "factory",
		"chapter": "hope",
		"hint": "工厂实验室",
		"unlocks_craft": "recipe_antibody_serum"
	},
	"file_military_orders": {
		"id": "file_military_orders",
		"type": "document",
		"name": "军令",
		"title": "清洗命令",
		"content": "【绝密】接上级命令，执行最终清洗。所有生物目标，无论感染与否，全部清除。不留活口",
		"location": "ruins",
		"chapter": "military_coverup",
		"hint": "废墟中的军官尸体"
	}
}

# ===== 剧情章节 =====
const STORY_CHAPTERS: Dictionary = {
	"outbreak_beginning": {
		"title": "爆发之初",
		"description": "疫情是如何开始的",
		"required_clues": ["diary_doctor_1", "diary_nurse_1", "file_news_article"],
		"reward": "了解疫情起源"
	},
	"survival_struggle": {
		"title": "生存挣扎",
		"description": "普通人的求生之路",
		"required_clues": ["diary_survivor_1", "recording_mother", "map_supply_cache"],
		"reward": "解锁更多生存技能"
	},
	"conspiracy": {
		"title": "阴谋",
		"description": "真相远比想象的可怕",
		"required_clues": ["recording_cdc", "photo_evidence", "file_cdc_report"],
		"reward": "了解真相"
	},
	"military_coverup": {
		"title": "军事掩盖",
		"description": "军方的秘密行动",
		"required_clues": ["diary_soldier", "photo_quarantine", "file_military_orders"],
		"reward": "了解军方计划"
	},
	"innocence_lost": {
		"title": "失去的纯真",
		"description": "这场灾难中最无辜的受害者",
		"required_clues": ["diary_child", "photo_family"],
		"reward": "情感共鸣"
	},
	"hope": {
		"title": "希望",
		"description": "即使在黑暗中，希望依然存在",
		"required_clues": ["photo_survivors", "file_research_notes"],
		"reward": "解锁真结局条件"
	},
	"escape_plan": {
		"title": "逃离计划",
		"description": "找到离开这座城市的方",
		"required_clues": ["map_underground"],
		"reward": "解锁森林区域"
	}
}

# ===== 当前状态 =====
var _found_clues: Array[String] = []
var _unlocked_chapters: Array[String] = []
var _new_game_plus_data: Dictionary = {}
var _current_playthrough: int = 1

func _ready():
	print("[StoryClueSystem] 环境叙事系统已初始化")
	_load_new_game_plus_data()

# ===== 线索管理 =====

## 发现线索
func discover_clue(clue_id: String, location: String = "") -> bool:
	if not CLUE_DATABASE.has(clue_id):
		return false
	
	if clue_id in _found_clues:
		return false
	
	var clue = CLUE_DATABASE[clue_id]
	
	# 检查解锁条件
	if clue.has("unlock_condition"):
		if not _check_unlock_condition(clue.unlock_condition):
			return false
	
	_found_clues.append(clue_id)
	
	clue_found.emit(clue_id, clue)
	
	# 检查章节解锁
	_check_chapter_unlock(clue.get("chapter", ""))
	
	# 处理额外奖励
	_process_clue_rewards(clue)
	
	print("[StoryClueSystem] 发现线索: %s" % clue.name)
	return true

func _check_unlock_condition(condition: String) -> bool:
	match condition:
		"visit_hospital":
			return GameState and GameState.player_position == "hospital"
		"new_game_plus":
			return _current_playthrough > 1
		"all_chapters":
			return _unlocked_chapters.size() >= 6
		_:
			return true

func _check_chapter_unlock(chapter_id: String):
	if chapter_id.is_empty() or chapter_id in _unlocked_chapters:
		return
	
	if not STORY_CHAPTERS.has(chapter_id):
		return
	
	var chapter = STORY_CHAPTERS[chapter_id]
	var required = chapter.required_clues
	
	# 检查是否收集齐所需线索
	var found_count = 0
	for clue_id in required:
		if clue_id in _found_clues:
			found_count += 1
	
	if found_count >= required.size():
		_unlock_chapter(chapter_id)

func _unlock_chapter(chapter_id: String):
	_unlocked_chapters.append(chapter_id)
	
	var chapter = STORY_CHAPTERS[chapter_id]
	story_chapter_unlocked.emit(chapter_id, chapter.title)
	
	print("[StoryClueSystem] 解锁章节: %s" % chapter.title)
	
	# 检查是否所有章节都解锁
	if _unlocked_chapters.size() >= STORY_CHAPTERS.size():
		new_game_plus_unlocked.emit()

func _process_clue_rewards(clue: Dictionary):
	# 解锁地点
	if clue.has("unlocks_location"):
		var location = clue.unlocks_location
		if MapModule and not MapModule._is_unlocked(location):
			MapModule.unlock_location(location)
	
	# 解锁制作配方
	if clue.has("unlocks_craft"):
		var craft_id = str(clue.unlocks_craft)
		if CraftingSystem and CraftingSystem.has_method("unlock_recipe"):
			CraftingSystem.unlock_recipe(craft_id)
	
	# 揭示战利品
	if clue.has("reveals_loot"):
		# 可以在这里添加揭示附近隐藏战利品的逻辑
		pass

## 获取地点可发现的线索
func get_available_clues(location: String) -> Array:
	var available = []
	
	for clue_id in CLUE_DATABASE.keys():
		if clue_id in _found_clues:
			continue
		
		var clue = CLUE_DATABASE[clue_id]
		if clue.get("location", "") == location:
			available.append(clue)
	
	return available

## 尝试发现线索（随机）
func try_discover_clue(location: String) -> bool:
	var available = get_available_clues(location)
	
	if available.is_empty():
		return false
	
	# 随机选择一个线索
	var clue = available[randi() % available.size()]
	discover_clue(clue.id, location)
	
	return true

## 搜索地点寻找线索
func search_for_clues(location: String) -> Array:
	var found = []
	
	# 基础发现概率
	var base_chance = 0.3
	
	# 感知技能加成
	var skill_system = get_node_or_null("/root/SkillSystem")
	if skill_system:
		base_chance += skill_system.get_skill_level("perception") * 0.05
	
	# 获取该地点所有可用线索
	var available = get_available_clues(location)
	
	for clue in available:
		if randf() < base_chance:
			if discover_clue(clue.id, location):
				found.append(clue)
	
	return found

# ===== 查询 =====

func get_clue(clue_id: String) -> Dictionary:
	return CLUE_DATABASE.get(clue_id, {})

func get_found_clues() -> Array:
	return _found_clues.duplicate()

func has_found_clue(clue_id: String) -> bool:
	return clue_id in _found_clues

func get_found_clues_by_type(clue_type: String) -> Array:
	var result = []
	for clue_id in _found_clues:
		var clue = CLUE_DATABASE.get(clue_id, {})
		if clue.get("type", "") == clue_type:
			result.append(clue)
	return result

func get_clue_progress() -> Dictionary:
	var total = CLUE_DATABASE.size()
	var found = _found_clues.size()
	
	return {
		"found": found,
		"total": total,
		"percentage": float(found) / total * 100,
		"by_type": {
			"diary": get_found_clues_by_type("diary").size(),
			"recording": get_found_clues_by_type("recording").size(),
			"photo": get_found_clues_by_type("photo").size(),
			"map": get_found_clues_by_type("map").size(),
			"document": get_found_clues_by_type("document").size()
		}
	}

# ===== 章节 =====

func get_chapter(chapter_id: String) -> Dictionary:
	return STORY_CHAPTERS.get(chapter_id, {})

func get_unlocked_chapters() -> Array:
	return _unlocked_chapters.duplicate()

func is_chapter_unlocked(chapter_id: String) -> bool:
	return chapter_id in _unlocked_chapters

func get_chapter_progress() -> Dictionary:
	var total = STORY_CHAPTERS.size()
	var unlocked = _unlocked_chapters.size()
	
	return {
		"unlocked": unlocked,
		"total": total,
		"percentage": float(unlocked) / total * 100
	}

# ===== 多周目系统 =====

func _load_new_game_plus_data():
	# 从存档加载多周目数据
	var save_system = get_node_or_null("/root/SaveSystem")
	if save_system and save_system.has_method("get_global_data"):
		var global_data = save_system.get_global_data()
		_new_game_plus_data = global_data.get("new_game_plus", {})
		_current_playthrough = global_data.get("playthrough_count", 1)

func get_new_game_plus_bonus() -> Dictionary:
	var bonus = {
		"extra_hp": 0,
		"extra_stamina": 0,
		"knowledge_bonus": 0,
		"starting_items": []
	}
	
	if _current_playthrough > 1:
		# 多周目奖励
		bonus.extra_hp = (_current_playthrough - 1) * 10
		bonus.extra_stamina = (_current_playthrough - 1) * 10
		bonus.knowledge_bonus = (_current_playthrough - 1) * 0.1
		
		# 继承已解锁的线索知识
		if _new_game_plus_data.has("found_clues"):
			bonus.known_clues = _new_game_plus_data.found_clues
	
	return bonus

func prepare_new_game_plus():
	# 保存本周目数据用于下周目继承
	_new_game_plus_data = {
		"found_clues": _found_clues.duplicate(),
		"unlocked_chapters": _unlocked_chapters.duplicate(),
		"completed": _unlocked_chapters.size() >= STORY_CHAPTERS.size()
	}
	
	_current_playthrough += 1
	
	# 保存到全局存档
	var save_system = get_node_or_null("/root/SaveSystem")
	if save_system and save_system.has_method("save_global_data"):
		save_system.save_global_data({
			"new_game_plus": _new_game_plus_data,
			"playthrough_count": _current_playthrough
		})

func reset_for_new_game():
	_found_clues.clear()
	_unlocked_chapters.clear()
	
	# 应用多周目奖励
	var bonus = get_new_game_plus_bonus()
	if GameState:
		GameState.player_max_hp += bonus.extra_hp
		GameState.player_hp = GameState.player_max_hp

# ===== 序列化 =====
func serialize() -> Dictionary:
	return {
		"found_clues": _found_clues,
		"unlocked_chapters": _unlocked_chapters,
		"current_playthrough": _current_playthrough,
		"new_game_plus_data": _new_game_plus_data
	}

func deserialize(data: Dictionary):
	_found_clues = data.get("found_clues", [])
	_unlocked_chapters = data.get("unlocked_chapters", [])
	_current_playthrough = data.get("current_playthrough", 1)
	_new_game_plus_data = data.get("new_game_plus_data", {})
	
	print("[StoryClueSystem] 叙事数据已加载，已发现 %d 条线索" % _found_clues.size())

