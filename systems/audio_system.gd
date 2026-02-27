extends Node
# AudioSystem - 音效系统
# 管理所有游戏音效和背景音乐

# ===== 音效类型枚举 =====
enum SoundType {
	UI_CLICK,      # UI点击
	UI_HOVER,      # UI悬停
	ITEM_PICKUP,   # 拾取物品
	ITEM_DROP,     # 丢弃物品
	WEAPON_ATTACK, # 武器攻击
	WEAPON_RELOAD, # 武器装填
	FOOTSTEP,      # 脚步"
	DAMAGE_TAKEN,  # 受到伤害
	DAMAGE_DEALT,  # 造成伤害
	ENEMY_DEATH,   # 敌人死亡
	LEVEL_UP,      # 升级
	QUEST_COMPLETE,# 任务完成
	DIALOG_OPEN,   # 对话框打开
	DIALOG_CLOSE   # 对话框关"
}

# ===== 音效文件路径配置 =====
const SOUND_PATHS = {
	"ui_click": "res://assets/audio/ui/click.wav",
	"ui_hover": "res://assets/audio/ui/hover.wav",
	"item_pickup": "res://assets/audio/items/pickup.wav",
	"item_drop": "res://assets/audio/items/drop.wav",
	"weapon_attack_melee": "res://assets/audio/weapons/melee_swing.wav",
	"weapon_attack_ranged": "res://assets/audio/weapons/gunshot.wav",
	"weapon_reload": "res://assets/audio/weapons/reload.wav",
	"footstep": "res://assets/audio/player/footstep.wav",
	"damage_taken": "res://assets/audio/combat/damage_taken.wav",
	"damage_dealt": "res://assets/audio/combat/damage_dealt.wav",
	"enemy_death": "res://assets/audio/combat/enemy_death.wav",
	"level_up": "res://assets/audio/ui/level_up.wav",
	"quest_complete": "res://assets/audio/ui/quest_complete.wav",
	"dialog_open": "res://assets/audio/ui/dialog_open.wav",
	"dialog_close": "res://assets/audio/ui/dialog_close.wav"
}

# ===== 背景音乐 =====
const BGM_PATHS = {
	"main_menu": "res://assets/audio/bgm/main_menu.ogg",
	"safehouse": "res://assets/audio/bgm/safehouse.ogg",
	"exploration": "res://assets/audio/bgm/exploration.ogg",
	"combat": "res://assets/audio/bgm/combat.ogg",
	"boss": "res://assets/audio/bgm/boss.ogg"
}

# ===== 音频播放"=====
var _sfx_players: Array[AudioStreamPlayer] = []
var _bgm_player: AudioStreamPlayer = null
var _current_bgm: String = ""

# ===== 设置 =====
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var bgm_volume: float = 0.7

func _ready():
	print("[AudioSystem] 音效系统已初始化")
	_setup_audio_players()

func _setup_audio_players():
	# 创建SFX播放器池"0个）
	for i in range(10):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)
	
	# 创建BGM播放"
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)

# ===== 播放音效 =====

func play_sfx(sound_name: String, volume_db: float = 0.0):
	var path = SOUND_PATHS.get(sound_name, "")
	if path.is_empty():
		push_warning("[AudioSystem] 未知音效: " + sound_name)
		return
	
	# 检查文件是否存"
	if not FileAccess.file_exists(path):
		# 使用占位符音效或静音
		print("[AudioSystem] 音效文件不存: " + path)
		return
	
	# 获取空闲播放"
	var player = _get_free_sfx_player()
	if not player:
		return
	
	# 加载并播"
	var stream = load(path)
	if stream:
		player.stream = stream
		player.volume_db = volume_db + (sfx_volume - 1.0) * 20.0
		player.play()

func play_sfx_by_type(sound_type: int, volume_db: float = 0.0):
	var sound_name = _get_sound_name_by_type(sound_type)
	play_sfx(sound_name, volume_db)

func _get_sound_name_by_type(sound_type: int):
	match sound_type:
		SoundType.UI_CLICK: return "ui_click"
		SoundType.UI_HOVER: return "ui_hover"
		SoundType.ITEM_PICKUP: return "item_pickup"
		SoundType.ITEM_DROP: return "item_drop"
		SoundType.WEAPON_ATTACK: return "weapon_attack_melee"
		SoundType.WEAPON_RELOAD: return "weapon_reload"
		SoundType.FOOTSTEP: return "footstep"
		SoundType.DAMAGE_TAKEN: return "damage_taken"
		SoundType.DAMAGE_DEALT: return "damage_dealt"
		SoundType.ENEMY_DEATH: return "enemy_death"
		SoundType.LEVEL_UP: return "level_up"
		SoundType.QUEST_COMPLETE: return "quest_complete"
		SoundType.DIALOG_OPEN: return "dialog_open"
		SoundType.DIALOG_CLOSE: return "dialog_close"
		_: return ""

func _get_free_sfx_player():
	for player in _sfx_players:
		if not player.playing:
			return player
	
	# 如果没有空闲播放器，找播放最久的
	var oldest_player = _sfx_players[0]
	return oldest_player

# ===== 播放背景音乐 =====

func play_bgm(bgm_name: String, fade_time: float = 2.0):
	if bgm_name == _current_bgm:
		return
	
	var path = BGM_PATHS.get(bgm_name, "")
	if path.is_empty():
		push_warning("[AudioSystem] 未知BGM: " + bgm_name)
		return
	
	if not FileAccess.file_exists(path):
		print("[AudioSystem] BGM文件不存: " + path)
		return
	
	_current_bgm = bgm_name
	
	# 淡入淡出效果
	if _bgm_player.playing:
		_fade_out_bgm(fade_time / 2.0)
		await get_tree().create_timer(fade_time / 2.0).timeout
	
	var stream = load(path)
	if stream:
		_bgm_player.stream = stream
		_bgm_player.volume_db = (bgm_volume - 1.0) * 20.0
		_bgm_player.play()
		_fade_in_bgm(fade_time / 2.0)

func _fade_out_bgm(duration: float):
	var start_volume = _bgm_player.volume_db
	var tween = create_tween()
	tween.tween_property(_bgm_player, "volume_db", -80.0, duration)

func _fade_in_bgm(duration: float):
	var target_volume = (bgm_volume - 1.0) * 20.0
	_bgm_player.volume_db = -80.0
	var tween = create_tween()
	tween.tween_property(_bgm_player, "volume_db", target_volume, duration)

func stop_bgm(fade_time: float = 2.0):
	_current_bgm = ""
	_fade_out_bgm(fade_time)
	await get_tree().create_timer(fade_time).timeout
	_bgm_player.stop()

# ===== 音量控制 =====

func set_master_volume(volume: float):
	master_volume = clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, (master_volume - 1.0) * 20.0)

func set_sfx_volume(volume: float):
	sfx_volume = clampf(volume, 0.0, 1.0)
	var sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, (sfx_volume - 1.0) * 20.0)

func set_bgm_volume(volume: float):
	bgm_volume = clampf(volume, 0.0, 1.0)
	var bgm_bus = AudioServer.get_bus_index("BGM")
	if bgm_bus >= 0:
		AudioServer.set_bus_volume_db(bgm_bus, (bgm_volume - 1.0) * 20.0)
	
	# 更新当前播放的BGM音量
	if _bgm_player.playing:
		_bgm_player.volume_db = (bgm_volume - 1.0) * 20.0

# ===== 便捷方法 =====

func play_attack_sound(is_melee: bool):
	var sound_name = "weapon_attack_melee" if is_melee else "weapon_attack_ranged"
	play_sfx(sound_name)

func play_ui_click():
	play_sfx("ui_click", -10.0)  # UI音效稍微小一"

func play_item_pickup():
	play_sfx("item_pickup")

func play_footstep():
	play_sfx("footstep", -15.0)  # 脚步声小一"

# ===== 保存/加载设置 =====

func get_save_data():
	return {
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"bgm_volume": bgm_volume
	}

func load_save_data(data: Dictionary):
	set_master_volume(data.get("master_volume", 1.0))
	set_sfx_volume(data.get("sfx_volume", 1.0))
	set_bgm_volume(data.get("bgm_volume", 0.7))
	print("[AudioSystem] 音频设置已加")

