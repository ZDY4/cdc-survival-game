extends CharacterBody2D
## NPC基类
## 场景中的NPC实体，包含所有组件

class_name NPCBase

# ========== 信号 ==========
signal npc_died(npc_id: String)
signal npc_recruited(npc_id: String)
signal npc_mood_changed(mood_type: String, new_value: int, old_value: int)
signal interaction_started(npc_id: String)
signal interaction_ended(npc_id: String)
signal dialog_started
signal dialog_ended
signal trade_started
signal trade_ended

# ========== 组件引用 ==========
@onready var dialog_component: NPCDialogComponent = $DialogComponent
@onready var trade_component: NPCTradeComponent = $TradeComponent
@onready var mood_component: NPCMoodComponent = $MoodComponent
@onready var memory_component: NPCMemoryComponent = $MemoryComponent
@onready var recruitment_component: NPCRecruitmentComponent = $RecruitmentComponent

# ========== 节点引用 ==========
@onready var sprite: Sprite2D = $Sprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var name_label: Label = $NameLabel
@onready var emote_bubble: Control = $EmoteBubble

# ========== 数据 ==========
var npc_data: NPCData
var npc_id: String:
	get: return npc_data.id if npc_data else ""
var npc_name: String:
	get: return npc_data.name if npc_data else ""
var current_location: String:
	get: return npc_data.current_location if npc_data else ""
	set(value):
		if npc_data:
			npc_data.current_location = value

# ========== 状态 ==========
var is_player_near: bool = false
var is_busy: bool = false

# ========== 配置 ==========
@export var interaction_radius: float = 60.0
@export var show_name_above: bool = true
@export var emote_duration: float = 2.0

func _ready():
	_setup_collision()
	_setup_visuals()
	_setup_interaction()

func _setup_collision():
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)

func _setup_visuals():
	# 加载立绘/头像
	if npc_data and npc_data.portrait_path and sprite:
		var texture = load(npc_data.portrait_path)
		if texture:
			sprite.texture = texture
	
	# 显示名字
	if name_label and show_name_above and npc_data:
		name_label.text = npc_data.get_display_name()
		name_label.visible = true

func _setup_interaction():
	# 初始化组件
	if dialog_component:
		dialog_component.initialize(self)
	if trade_component:
		trade_component.initialize(self)
	if mood_component:
		mood_component.initialize(self)
	if memory_component:
		memory_component.initialize(self)
	if recruitment_component:
		recruitment_component.initialize(self)

# ========== 初始化 ==========

func initialize(data: NPCData):
	npc_data = data
	_setup_visuals()
	_setup_components()

func _setup_components():
	if dialog_component:
		dialog_component.dialog_tree = _get_dialog_tree()

func _get_dialog_tree() -> Dictionary:
	# 根据NPC类型返回默认对话树，或从数据库加载
	return _create_default_dialog_tree()

func _create_default_dialog_tree() -> Dictionary:
	var tree = {
		"start": {
			"text": "你好，我是%s。有什么我可以帮你的吗？" % npc_name,
			"emotion": "normal",
			"speaker": npc_name,
			"options": []
		}
	}
	
	# 根据能力添加选项
	if can_trade():
		tree.start.options.append({
			"text": "我想看看你的商品",
			"next_node": "trade",
			"actions": [{"type": "open_trade"}],
			"mood_effects": {"friendliness": 2}
		})
	
	if can_give_quest():
		tree.start.options.append({
			"text": "你有什么任务需要帮忙吗？",
			"next_node": "quest",
			"conditions": [{"type": "has_available_quests"}]
		})
	
	if can_be_recruited():
		tree.start.options.append({
			"text": "我想邀请你加入我的队伍",
			"next_node": "recruit_check",
			"conditions": [{"type": "can_recruit"}]
		})
	
	# 添加告别选项
	tree.start.options.append({
		"text": "再见",
		"next_node": "end"
	})
	
	return tree

# ========== 交互功能 ==========

func is_interactable() -> bool:
	if not npc_data:
		return false
	return npc_data.is_interactable() and not is_busy

func can_trade() -> bool:
	return npc_data and npc_data.can_trade and npc_data.state.trade_enabled

func can_be_recruited() -> bool:
	return npc_data and npc_data.can_recruit and not npc_data.state.is_recruited

func can_give_quest() -> bool:
	return npc_data and npc_data.can_give_quest

## 开始对话
func start_dialog() -> bool:
	if not is_interactable():
		return false
	
	if not dialog_component:
		push_error("[NPCBase] 没有对话组件")
		return false
	
	is_busy = true
	interaction_started.emit(npc_id)
	dialog_started.emit()
	
	# 记录见面
	if memory_component:
		memory_component.on_player_met()
	
	# 开始对话流程
	var success = await dialog_component.start_dialog()
	
	is_busy = false
	dialog_ended.emit()
	interaction_ended.emit(npc_id)
	
	return success

## 打开交易界面
func open_trade_ui() -> bool:
	if not can_trade():
		return false
	
	if not trade_component:
		return false
	
	is_busy = true
	trade_started.emit()
	
	var success = await trade_component.open_trade_ui()
	
	is_busy = false
	trade_ended.emit()
	
	return success

## 检查招募条件
func check_recruitment_conditions() -> Dictionary:
	if not recruitment_component:
		return {"success": false, "reason": "此NPC不可招募"}
	
	return recruitment_component.check_conditions()

## 被招募
func on_recruited() -> bool:
	if not recruitment_component:
		return false
	
	var success = recruitment_component.on_recruited()
	if success:
		npc_recruited.emit(npc_id)
		NPCModule.npc_recruited.emit(npc_id)
		queue_free()  # 从场景中移除，加入队伍
	
	return success

## 改变情绪
func change_mood(mood_type: String, delta: int):
	if not npc_data or not mood_component:
		return
	
	var old_value = npc_data.mood.get(mood_type, 0)
	mood_component.change_mood(mood_type, delta)
	var new_value = npc_data.mood.get(mood_type, 0)
	
	if old_value != new_value:
		npc_mood_changed.emit(mood_type, new_value, old_value)
		NPCModule.npc_mood_changed.emit(npc_id, mood_type, new_value)

## 获取当前立绘（根据情绪）
func get_current_portrait() -> String:
	if not npc_data:
		return ""
	
	var emotion = mood_component.get_current_emotion() if mood_component else "normal"
	# 根据情绪返回对应的表情立绘路径
	return npc_data.get_expression_path(emotion)

# ========== 事件处理 ==========

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		is_player_near = true
		_on_player_entered()

func _on_body_exited(body: Node):
	if body.is_in_group("player"):
		is_player_near = false
		_on_player_exited()

func _on_player_entered():
	# 显示交互提示
	_show_interaction_prompt()
	
	# 根据友好度决定是否主动打招呼
	if npc_data and npc_data.memory.met_player:
		if npc_data.mood.friendliness > 60:
			_show_emote("friendly")
	else:
		# 第一次见面
		_show_emote("curious")

func _on_player_exited():
	_hide_interaction_prompt()
	_hide_emote()

func _on_time_advanced(hours: int):
	# 处理日程
	if npc_data and not npc_data.schedule.is_empty():
		_check_schedule()

func _check_schedule():
	# 检查当前时间是否应该移动到其他位置
	pass

func on_attacked(attacker: Node):
	# 被攻击时的反应
	if npc_data:
		npc_data.state.is_hostile = true
		change_mood("anger", 20)
		change_mood("friendliness", -10)
		_show_emote("angry")

func on_helped(help_type: String):
	# 被帮助时的反应
	change_mood("friendliness", 10)
	change_mood("trust", 5)
	_show_emote("happy")
	
	if memory_component:
		memory_component.record_player_action("helped", {"type": help_type})

# ========== UI显示 ==========

func _show_interaction_prompt():
	if not is_interactable():
		return
	
	# 创建交互提示
	var prompt = Label.new()
	prompt.text = "[E] 与 %s 交谈" % npc_name
	prompt.position = Vector2(0, -80)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color.YELLOW)
	add_child(prompt)
	
	# 动画效果
	var tween = create_tween()
	tween.tween_property(prompt, "position:y", -90, 0.5)
	tween.tween_property(prompt, "position:y", -80, 0.5)
	tween.set_loops()
	
	prompt.name = "InteractionPrompt"

func _hide_interaction_prompt():
	var prompt = get_node_or_null("InteractionPrompt")
	if prompt:
		prompt.queue_free()

func _show_emote(emote_type: String):
	if not emote_bubble:
		return
	
	var icon = ""
	match emote_type:
		"friendly":
			icon = "😊"
		"happy":
			icon = "😄"
		"angry":
			icon = "😠"
		"curious":
			icon = "🤔"
		"surprised":
			icon = "😲"
		"sad":
			icon = "😢"
		_:
			icon = "💬"
	
	# 显示表情气泡
	var label = Label.new()
	label.text = icon
	label.add_theme_font_size_override("font_size", 32)
	emote_bubble.add_child(label)
	emote_bubble.visible = true
	
	# 延迟隐藏
	await get_tree().create_timer(emote_duration).timeout
	_hide_emote()

func _hide_emote():
	if emote_bubble:
		for child in emote_bubble.get_children():
			child.queue_free()
		emote_bubble.visible = false

func show_floating_text(text: String, color: Color = Color.WHITE):
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(0, -60)
	add_child(label)
	
	# 向上飘动动画
	var tween = create_tween()
	tween.tween_property(label, "position:y", -100, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0, 1.0)
	
	await tween.finished
	label.queue_free()

# ========== 位置管理 ==========

func set_location(location: String):
	current_location = location

func set_position_2d(pos: Vector2):
	global_position = pos

# ========== 保存/加载 ==========

func serialize() -> Dictionary:
	if not npc_data:
		return {}
	return npc_data.serialize()

func deserialize(data: Dictionary):
	if npc_data:
		npc_data.deserialize(data)
