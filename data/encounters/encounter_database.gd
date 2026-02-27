extends Node
# EncounterDatabase - 遭遇数据库
# 包含15个遭遇事件：医院3个、超市3个、学校3个、森林2个、公路2个、废墟2个

const ENCOUNTER_DATA: Dictionary = {
	# ===== 医院类遭遇 (3个) =====
	"hospital_emergency_room": {
		"id": "hospital_emergency_room",
		"name": "急诊室困境",
		"locations": ["hospital"],
		"description": "你进入了一间废弃的急诊室。手术台上的设备已经锈迹斑斑，但医药柜里似乎还有东西。突然，你听到走廊传来脚步声——可能是其他幸存者，也可能是感染者。",
		"choices": [
			{
				"text": "快速搜刮医药柜",
				"skill_check": "agility",
				"difficulty": 12,
				"success_outcome": {
					"text": "你迅速搜刮了医药柜，找到了一些有用的药品后安全撤离。",
					"items": [{"id": "first_aid_kit", "count": 1}, {"id": "painkiller", "count": 2}],
					"xp": 15
				},
				"fail_outcome": {
					"text": "你动作太慢了，被感染者发现！你不得不边战边退。",
					"hp_loss": 15,
					"items": [{"id": "bandage", "count": 1}]
				}
			},
			{
				"text": "躲起来观察",
				"skill_check": "stealth",
				"difficulty": 10,
				"success_outcome": {
					"text": "你成功躲藏起来，观察发现是一队友善的幸存者。他们留下了一些物资后离开。",
					"items": [{"id": "medicine", "count": 1}, {"id": "water_bottle", "count": 2}],
					"xp": 20
				},
				"fail_outcome": {
					"text": "你躲藏时发出了声响，惊动了外面的生物。",
					"hp_loss": 10
				}
			},
			{
				"text": "正面迎击",
				"skill_check": "combat",
				"difficulty": 14,
				"success_good": {
					"text": "你击败了感染者，搜刮了整个急诊室！",
					"items": [{"id": "first_aid_kit", "count": 2}, {"id": "antibiotics", "count": 1}],
					"xp": 30
				},
				"success_outcome": {
					"text": "经过一番战斗，你击退了感染者，获得了一些药品。",
					"items": [{"id": "bandage", "count": 2}],
					"xp": 15,
					"hp_loss": 10
				},
				"fail_outcome": {
					"text": "敌人数量太多，你被迫撤退，受了一些伤。",
					"hp_loss": 25
				}
			},
			{
				"text": "悄悄离开",
				"outcome": {
					"text": "你决定不冒险，安全地离开了急诊室。",
					"xp": 5
				}
			}
		],
		"weight": 1.0
	},
	
	"hospital_morgue": {
		"id": "hospital_morgue",
		"name": "停尸房惊魂",
		"locations": ["hospital"],
		"description": "为了寻找物资，你不得不进入医院的停尸房。阴冷的环境中，你注意到一具'尸体'的手指似乎动了一下...",
		"choices": [
			{
				"text": "仔细检查那具尸体",
				"skill_check": "perception",
				"difficulty": 11,
				"success_outcome": {
					"text": "你发现那是一个还活着的幸存者！救醒他后，他给了你一些珍贵的医疗物资作为感谢。",
					"items": [{"id": "first_aid_kit", "count": 1}, {"id": "rare_medicine", "count": 1}],
					"xp": 25
				},
				"fail_outcome": {
					"text": "那确实是一只感染者！它突然暴起攻击你。",
					"hp_loss": 20
				}
			},
			{
				"text": "用工具刺穿头部",
				"outcome": {
					"text": "你确保它不会突然复活，然后继续搜索。",
					"items": [{"id": "medical_scissors", "count": 1}],
					"xp": 10
				}
			},
			{
				"text": "无视它，搜索其他地方",
				"outcome": {
					"text": "你找到了一些基础医疗用品，但总觉得背后发凉。",
					"items": [{"id": "bandage", "count": 2}],
					"xp": 10
				}
			}
		],
		"weight": 0.8
	},
	
	"hospital_pharmacy": {
		"id": "hospital_pharmacy",
		"name": "药房锁柜",
		"locations": ["hospital"],
		"description": "你找到了医院的药房，但所有有价值的药品都锁在防弹玻璃后面的柜子里。",
		"choices": [
			{
				"text": "尝试撬锁",
				"skill_check": "lockpicking",
				"difficulty": 13,
				"success_outcome": {
					"text": "你成功打开了药柜！找到了大量的珍贵药品。",
					"items": [{"id": "antibiotics", "count": 2}, {"id": "painkiller", "count": 3}, {"id": "first_aid_kit", "count": 1}],
					"xp": 30
				},
				"fail_outcome": {
					"text": "锁太复杂了，你折腾了半天也没打开，还引来了感染者。",
					"hp_loss": 15,
					"time_cost": 1
				}
			},
			{
				"text": "用工具砸开",
				"outcome": {
					"text": "你用力砸开了玻璃，虽然拿到了一些药品，但巨大的噪音引来了危险。",
					"items": [{"id": "painkiller", "count": 2}, {"id": "bandage", "count": 1}],
					"hp_loss": 10,
					"xp": 15
				}
			},
			{
				"text": "寻找钥匙",
				"skill_check": "investigation",
				"difficulty": 10,
				"success_outcome": {
					"text": "你在值班室找到了钥匙！顺利打开了药柜。",
					"items": [{"id": "medicine", "count": 2}, {"id": "antibiotics", "count": 1}],
					"xp": 20
				},
				"fail_outcome": {
					"text": "你找了很久都没有找到钥匙，浪费时间。",
					"time_cost": 2
				}
			}
		],
		"weight": 1.0
	},
	
	# ===== 超市类遭遇 (3个) =====
	"supermarket_raiders": {
		"id": "supermarket_raiders",
		"name": "掠夺者遭遇",
		"locations": ["supermarket"],
		"description": "你进入超市寻找食物，却发现一群掠夺者正在搬运物资。他们还没有发现你。",
		"choices": [
			{
				"text": "尝试谈判",
				"skill_check": "negotiation",
				"difficulty": 13,
				"success_outcome": {
					"text": "你成功说服他们让你用一些物资交换安全通过。",
					"cost": {"items": [{"id": "scrap_metal", "count": 3}]},
					"items": [{"id": "canned_food", "count": 3}, {"id": "water_bottle", "count": 2}],
					"xp": 20
				},
				"fail_outcome": {
					"text": "谈判破裂！他们向你开火。",
					"hp_loss": 20
				}
			},
			{
				"text": "偷袭他们",
				"skill_check": "combat",
				"difficulty": 12,
				"success_outcome": {
					"text": "你成功偷袭，击败了他们并获得了所有物资！",
					"items": [{"id": "canned_food", "count": 5}, {"id": "water_bottle", "count": 3}, {"id": "weapon", "count": 1}],
					"xp": 25
				},
				"fail_outcome": {
					"text": "你被发现了，不得不边战边退。",
					"hp_loss": 25
				}
			},
			{
				"text": "悄悄绕过",
				"skill_check": "stealth",
				"difficulty": 9,
				"success_outcome": {
					"text": "你成功绕过他们，在货架上找到了一些物资。",
					"items": [{"id": "canned_food", "count": 2}, {"id": "snack", "count": 2}],
					"xp": 15
				},
				"fail_outcome": {
					"text": "你被发现了，他们追着你开枪。",
					"hp_loss": 15
				}
			},
			{
				"text": "离开",
				"outcome": {
					"text": "你选择不冒险，安全离开。",
					"xp": 5
				}
			}
		],
		"weight": 1.0
	},
	
	"supermarket_collapse": {
		"id": "supermarket_collapse",
		"name": "货架坍塌",
		"locations": ["supermarket"],
		"description": "你在超市深处搜索时，老化的货架突然开始倒塌！",
		"choices": [
			{
				"text": "快速闪避",
				"skill_check": "agility",
				"difficulty": 11,
				"success_outcome": {
					"text": "你灵活地躲开了倒塌的货架，并在废墟中发现了一些物资。",
					"items": [{"id": "canned_food", "count": 2}, {"id": "bottle", "count": 1}],
					"xp": 15
				},
				"fail_outcome": {
					"text": "你闪躲不及，被货架砸中了。",
					"hp_loss": 20
				}
			},
			{
				"text": "寻找掩体",
				"outcome": {
					"text": "你躲在一个结实的货架下，虽然安全但错过了搜刮的机会。",
					"xp": 5
				}
			}
		],
		"weight": 0.7
	},
	
	"supermarket_supply_cache": {
		"id": "supermarket_supply_cache",
		"name": "隐藏储藏室",
		"locations": ["supermarket"],
		"description": "你在超市仓库发现了一扇隐蔽的门，似乎是一个储藏室。门上有一个密码锁。",
		"choices": [
			{
				"text": "尝试破解密码",
				"skill_check": "intelligence",
				"difficulty": 12,
				"success_outcome": {
					"text": "你成功破解了密码！储藏室里堆满了食物和物资。",
					"items": [{"id": "canned_food", "count": 5}, {"id": "water_bottle", "count": 4}, {"id": "first_aid_kit", "count": 1}],
					"xp": 25
				},
				"fail_outcome": {
					"text": "你尝试了很多次都没有成功，还触发了警报。",
					"hp_loss": 10
				}
			},
			{
				"text": "强行撬开",
				"skill_check": "strength",
				"difficulty": 13,
				"success_outcome": {
					"text": "你用蛮力打开了门，获得了大量物资。",
					"items": [{"id": "canned_food", "count": 4}, {"id": "water_bottle", "count": 3}],
					"xp": 20,
					"hp_loss": 5
				},
				"fail_outcome": {
					"text": "门太结实了，你筋疲力尽也没能打开。",
					"stamina": 30
				}
			},
			{
				"text": "放弃离开",
				"outcome": {
					"text": "你觉得不值得冒险，离开了。",
					"xp": 5
				}
			}
		],
		"weight": 0.8
	},
	
	# ===== 学校类遭遇 (3个) =====
	"school_children": {
		"id": "school_children",
		"name": "幸存的孩子",
		"locations": ["school"],
		"description": "在学校教室里，你发现了一群躲藏的孩子。他们看起来营养不良，但眼神警惕。",
		"choices": [
			{
				"text": "分享食物",
				"cost": {"items": [{"id": "canned_food", "count": 2}]},
				"outcome": {
					"text": "孩子们感激地接受了食物，并告诉你一个秘密储藏室的位置。",
					"items": [{"id": "school_map", "count": 1}, {"id": "medical_supplies", "count": 1}],
					"xp": 30,
					"heal": 10  # 精神恢复
				}
			},
			{
				"text": "询问信息",
				"skill_check": "negotiation",
				"difficulty": 10,
				"success_outcome": {
					"text": "孩子们告诉你周围的危险区域和资源位置。",
					"xp": 15
				},
				"fail_outcome": {
					"text": "孩子们很害怕，拒绝和你交流。",
					"xp": 5
				}
			},
			{
				"text": "无视他们离开",
				"outcome": {
					"text": "你选择了离开，但心里有些不安。",
					"xp": 5
				}
			}
		],
		"weight": 0.9
	},
	
	"school_zombie_teacher": {
		"id": "school_zombie_teacher",
		"name": "变异教师",
		"locations": ["school"],
		"description": "你在教师办公室遇到了一个穿着破烂西装的变异体。它的动作比普通感染者更敏捷，似乎是学校的老师变异而来。",
		"choices": [
			{
				"text": "正面战斗",
				"skill_check": "combat",
				"difficulty": 14,
				"success_outcome": {
					"text": "你击败了变异教师，在它的办公桌里找到了一些有用的东西。",
					"items": [{"id": "stationery", "count": 3}, {"id": "keys", "count": 1}, {"id": "personal_items", "count": 1}],
					"xp": 25
				},
				"fail_outcome": {
					"text": "这个变异体太强了，你受了重伤才逃出来。",
					"hp_loss": 30
				}
			},
			{
				"text": "利用环境陷阱",
				"skill_check": "intelligence",
				"difficulty": 12,
				"success_outcome": {
					"text": "你利用办公室的书架将变异体困住，安全地搜索了房间。",
					"items": [{"id": "keys", "count": 1}, {"id": "documents", "count": 1}],
					"xp": 20
				},
				"fail_outcome": {
					"text": "你的计划失败了，变异体挣脱了束缚。",
					"hp_loss": 20
				}
			},
			{
				"text": "逃跑",
				"skill_check": "agility",
				"difficulty": 9,
				"success_outcome": {
					"text": "你成功逃脱了。",
					"xp": 5
				},
				"fail_outcome": {
					"text": "你逃跑时被它抓伤了。",
					"hp_loss": 15
				}
			}
		],
		"weight": 1.0
	},
	
	"school_library_secret": {
		"id": "school_library_secret",
		"name": "图书馆密室",
		"locations": ["school"],
		"description": "在图书馆的深处，你发现了一个伪装成书架的暗门。门缝里透出一丝光亮。",
		"choices": [
			{
				"text": "进入密室",
				"outcome": {
					"text": "你发现了学校生存社团的秘密基地！里面有很多有用的物资和资料。",
					"items": [{"id": "survival_guide", "count": 1}, {"id": "canned_food", "count": 3}, {"id": "flashlight", "count": 1}, {"id": "rope", "count": 2}],
					"xp": 30
				}
			},
			{
				"text": "先观察再决定",
				"skill_check": "perception",
				"difficulty": 10,
				"success_outcome": {
					"text": "你仔细观察后发现密室是安全的，而且里面有人留下的物资。",
					"items": [{"id": "canned_food", "count": 2}, {"id": "map", "count": 1}],
					"xp": 20
				},
				"fail_outcome": {
					"text": "你犹豫太久，被路过的感染者发现了。",
					"hp_loss": 10
				}
			},
			{
				"text": "不进入",
				"outcome": {
					"text": "你觉得可能有危险，选择离开。",
					"xp": 5
				}
			}
		],
		"weight": 0.7
	},
	
	# ===== 森林类遭遇 (2个) =====
	"forest_wild_animals": {
		"id": "forest_wild_animals",
		"name": "野兽遭遇",
		"locations": ["forest"],
		"description": "你在森林中穿行时，遇到了一群变异的野狗。它们看起来饥饿且充满敌意。",
		"choices": [
			{
				"text": "尝试吓退它们",
				"skill_check": "survival",
				"difficulty": 11,
				"success_outcome": {
					"text": "你利用生存知识，用火把和声音成功吓退了野狗。",
					"xp": 20
				},
				"fail_outcome": {
					"text": "你的尝试激怒了它们，野狗群向你扑来！",
					"hp_loss": 25
				}
			},
			{
				"text": "爬上树躲避",
				"skill_check": "athletics",
				"difficulty": 10,
				"success_outcome": {
					"text": "你成功爬到树上，等野狗离开后安全下来。",
					"xp": 15
				},
				"fail_outcome": {
					"text": "你爬树时被野狗咬到了腿。",
					"hp_loss": 15
				}
			},
			{
				"text": "战斗",
				"skill_check": "combat",
				"difficulty": 13,
				"success_outcome": {
					"text": "你击杀了领头的野狗，其余的逃散了。你可以收获一些生肉。",
					"items": [{"id": "raw_meat", "count": 3}],
					"xp": 20
				},
				"fail_outcome": {
					"text": "野狗数量太多，你受了重伤才击退它们。",
					"hp_loss": 30
				}
			}
		],
		"weight": 1.0
	},
	
	"forest_lost_survivor": {
		"id": "forest_lost_survivor",
		"name": "迷路的幸存者",
		"locations": ["forest"],
		"description": "你在森林深处发现了一个迷路的幸存者。他看起来脱水严重，但还保持着清醒。",
		"choices": [
			{
				"text": "分享水和食物",
				"cost": {"items": [{"id": "water_bottle", "count": 1}], "hunger": 10},
				"outcome": {
					"text": "幸存者非常感激，告诉你森林中一个安全营地位置，并给了你一些弹药。",
					"items": [{"id": "ammo", "count": 10}, {"id": "map_fragment", "count": 1}],
					"xp": 25,
					"heal": 15
				}
			},
			{
				"text": "为他治疗",
				"skill_check": "medicine",
				"difficulty": 10,
				"success_outcome": {
					"text": "你成功帮助了他恢复。作为回报，他教了你一些野外生存技巧。",
					"xp": 30
					# 可以解锁生存技能
				},
				"fail_outcome": {
					"text": "你的治疗没有起到作用，他的情况恶化了。",
					"xp": 5
				}
			},
			{
				"text": "只给他指方向",
				"outcome": {
					"text": "你告诉他最近的出口方向，然后继续你的旅程。",
					"xp": 10
				}
			}
		],
		"weight": 0.8
	},
	
	# ===== 公路类遭遇 (2个) =====
	"highway_abandoned_vehicle": {
		"id": "highway_abandoned_vehicle",
		"name": "废弃车辆",
		"locations": ["street"],
		"description": "你在公路上发现了一辆废弃的军用吉普车。车窗已经破碎，但后备箱似乎还锁着。",
		"choices": [
			{
				"text": "撬开后备箱",
				"skill_check": "lockpicking",
				"difficulty": 11,
				"success_outcome": {
					"text": "你成功打开了后备箱！里面有一些军用物资。",
					"items": [{"id": "military_rations", "count": 2}, {"id": "ammo", "count": 15}, {"id": "flare", "count": 1}],
					"xp": 20
				},
				"fail_outcome": {
					"text": "你撬锁的声音引来了附近的感染者。",
					"hp_loss": 15
				}
			},
			{
				"text": "搜索车内",
				"outcome": {
					"text": "你在车内找到了一些有用的东西。",
					"items": [{"id": "map", "count": 1}, {"id": "water_bottle", "count": 1}],
					"xp": 10
				}
			},
			{
				"text": "继续赶路",
				"outcome": {
					"text": "你觉得不值得冒险，继续赶路。",
					"xp": 5
				}
			}
		],
		"weight": 1.0
	},
	
	"highway_ambush": {
		"id": "highway_ambush",
		"name": "公路伏击",
		"locations": ["street"],
		"description": "你走在公路上时，突然遭到伏击！几颗子弹打在你脚边，有人在路边的建筑里向你开枪。",
		"choices": [
			{
				"text": "找掩护还击",
				"skill_check": "combat",
				"difficulty": 13,
				"success_outcome": {
					"text": "你成功找到掩护并击退了伏击者。在他们身上找到了一些物资。",
					"items": [{"id": "ammo", "count": 10}, {"id": "bandage", "count": 1}],
					"xp": 25
				},
				"fail_outcome": {
					"text": "伏击者火力太猛，你受了伤才找到掩护。",
					"hp_loss": 25
				}
			},
			{
				"text": "逃跑",
				"skill_check": "agility",
				"difficulty": 11,
				"success_outcome": {
					"text": "你成功逃离了伏击圈。",
					"xp": 10
				},
				"fail_outcome": {
					"text": "你被子弹击中了。",
					"hp_loss": 20
				}
			},
			{
				"text": "趴下装死",
				"outcome": {
					"text": "你趴在地上装死，伏击者以为得手离开了。但你也浪费了很多时间。",
					"time_cost": 2,
					"xp": 10
				}
			}
		],
		"weight": 0.8,
		"time_requirement": "day"
	},
	
	# ===== 废墟类遭遇 (2个) =====
	"ruins_underground_bunker": {
		"id": "ruins_underground_bunker",
		"name": "地下掩体",
		"locations": ["factory", "subway"],
		"description": "在废墟中探索时，你意外发现了一个通往地下掩体的入口。铁门半开着，里面一片漆黑。",
		"choices": [
			{
				"text": "带着手电筒进入",
				"need_tool": "flashlight",
				"outcome": {
					"text": "有了手电筒的照明，你安全地探索了掩体，找到了大量生存物资。",
					"items": [{"id": "canned_food", "count": 4}, {"id": "water_bottle", "count": 3}, {"id": "radio", "count": 1}, {"id": "battery", "count": 2}],
					"xp": 30
				}
			},
			{
				"text": "摸黑进入",
				"skill_check": "perception",
				"difficulty": 12,
				"success_outcome": {
					"text": "虽然黑暗，但你凭借敏锐的感知找到了一些物资。",
					"items": [{"id": "canned_food", "count": 2}, {"id": "battery", "count": 1}],
					"xp": 15
				},
				"fail_outcome": {
					"text": "黑暗中你不小心触发了陷阱，还惊动了里面的感染者。",
					"hp_loss": 25
				}
			},
			{
				"text": "在门口观察",
				"outcome": {
					"text": "你在门口发现了其他人留下的记号，警告里面危险。你决定离开。",
					"xp": 10
				}
			}
		],
		"weight": 0.9
	},
	
	"ruins_radioactive_zone": {
		"id": "ruins_radioactive_zone",
		"name": "辐射区域",
		"locations": ["factory"],
		"description": "你注意到这片废墟的一些区域有辐射警告标志。但同时也看到一些物资散落在辐射区内。",
		"choices": [
			{
				"text": "快速冲进去拿物资",
				"skill_check": "agility",
				"difficulty": 11,
				"success_outcome": {
					"text": "你快速冲进去拿到了物资并成功撤离，只受到了轻微辐射。",
					"items": [{"id": "rare_materials", "count": 2}, {"id": "advanced_parts", "count": 1}],
					"xp": 20,
					"hp_loss": 10
				},
				"fail_outcome": {
					"text": "你在里面待太久了，受到了严重辐射。",
					"hp_loss": 35
				}
			},
			{
				"text": "寻找防护装备",
				"skill_check": "investigation",
				"difficulty": 12,
				"success_outcome": {
					"text": "你在附近找到了一件防护服！现在可以安全地搜索辐射区了。",
					"items": [{"id": "hazmat_suit", "count": 1}, {"id": "rare_materials", "count": 3}],
					"xp": 25
				},
				"fail_outcome": {
					"text": "你找了很久都没有找到防护装备。",
					"time_cost": 2
				}
			},
			{
				"text": "离开",
				"outcome": {
					"text": "你决定不值得冒险，离开了辐射区域。",
					"xp": 5
				}
			}
		],
		"weight": 0.7
	}
}

static func get_all_encounters() -> Dictionary:
	return ENCOUNTER_DATA.duplicate()

static func get_encounter(encounter_id: String) -> Dictionary:
	return ENCOUNTER_DATA.get(encounter_id, {}).duplicate()

static func get_encounters_by_location(location: String) -> Array:
	var result = []
	for encounter_id in ENCOUNTER_DATA.keys():
		var encounter = ENCOUNTER_DATA[encounter_id]
		if encounter.has("locations") and location in encounter.locations:
			result.append(encounter)
	return result
