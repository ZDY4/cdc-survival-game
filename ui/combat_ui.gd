extends Control
## 战斗UI - 完整的战斗界面，集成部位伤害系统

class_name CombatUI

# ========== 信号 ==========
signal attack_initiated(target_limb: int, attack_type: String)
signal defend_initiated
signal item_menu_requested
signal flee_requested
signal limb_targeting_started
signal limb_targeting_cancelled

# ========== 导出变量 ==========
@export var show_limb_selection: bool = true
@export var auto_target_functional: bool = true

# ========== 节点引用 ==========
@onready var player_limb_ui: LimbStatusUI = $PlayerPanel/LimbStatusUI
@onready var enemy_limb_ui: LimbStatusUI = $EnemyPanel/LimbStatusUI
@onready var action_buttons: HBoxContainer = $ActionPanel/ActionButtons
@onready var combat_log: RichTextLabel = $LogPanel/CombatLog
@onready var enemy_info: Panel = $EnemyPanel
@onready var limb_selection_panel: Panel = $LimbSelectionPanel

# 动作按钮
@onready var attack_btn: Button = $ActionPanel/ActionButtons/AttackButton
@onready var defend_btn: Button = $ActionPanel/ActionButtons/DefendButton
@onready var item_btn: Button = $ActionPanel/ActionButtons/ItemButton
@onready var flee_btn: Button = $ActionPanel/ActionButtons/FleeButton

# 部位选择按钮
@onready var head_btn: Button = $LimbSelectionPanel/Buttons/HeadButton
@onready var torso_btn: Button = $LimbSelectionPanel/Buttons/TorsoButton
@onready var left_arm_btn: Button = $LimbSelectionPanel/Buttons/LeftArmButton
@onready var right_arm_btn: Button = $LimbSelectionPanel/Buttons/RightArmButton
@onready var legs_btn: Button = $LimbSelectionPanel/Buttons/LegsButton
@onready var cancel_target_btn: Button = $LimbSelectionPanel/CancelButton

# ========== 状态变量 ==========
var combat_system: CombatSystem = null
var limb_system: LimbDamageSystem = null
var combat_module: CombatModule = null

var is_selecting_limb: bool = false
var selected_attack_type: String = "normal"  # normal, heavy, quick
var pending_action: String = ""

# 部位按钮映射
var limb_buttons: Dictionary = {}

# ========== 初始化 ==========
func _ready():
	_initialize_systems()
	_setup_ui()
	_connect_signals()
	_hide_limb_selection()

func _initialize_systems() -> void:
	if Engine.has_singleton("CombatSystem"):
		combat_system = Engine.get_singleton("CombatSystem")
	elif has_node("/root/CombatSystem"):
		combat_system = get_node("/root/CombatSystem")
	
	if Engine.has_singleton("LimbDamageSystem"):
		limb_system = Engine.get_singleton("LimbDamageSystem")
	elif has_node("/root/LimbDamageSystem"):
		limb_system = get_node("/root/LimbDamageSystem")
	
	if Engine.has_singleton("CombatModule"):
		combat_module = Engine.get_singleton("CombatModule")
	elif has_node("/root/CombatModule"):
		combat_module = get_node("/root/CombatModule")

func _setup_ui() -> void:
	# 初始化部位按钮映射
	limb_buttons = {
		LimbDamageSystem.LimbType.HEAD: head_btn,
		LimbDamageSystem.LimbType.TORSO: torso_btn,
		LimbDamageSystem.LimbType.LEFT_ARM: left_arm_btn,
		LimbDamageSystem.LimbType.RIGHT_ARM: right_arm_btn,
		LimbDamageSystem.LimbType.LEGS: legs_btn
	}
	
	# 设置部位按钮文本
	_update_limb_button_labels()
	
	# 初始化战斗日志
	if combat_log:
		combat_log.clear()
		combat_log.append_text("[color=gray]战斗准备就绪...[/color]\n")

func _connect_signals() -> void:
	# 连接战斗系统信号
	if combat_system:
		combat_system.combat_started.connect(_on_combat_started)
		combat_system.combat_ended.connect(_on_combat_ended)
		combat_system.turn_started.connect(_on_turn_started)
		combat_system.action_performed.connect(_on_action_performed)
		combat_system.damage_dealt.connect(_on_damage_dealt)
		combat_system.damage_taken.connect(_on_damage_taken)
		combat_system.combat_log_message.connect(_on_combat_log_message)
		combat_system.limb_target_selected.connect(_on_limb_target_selected)
	
	# 连接部位系统信号
	if limb_system:
		limb_system.limb_damaged.connect(_on_limb_damaged)
		limb_system.limb_broken.connect(_on_limb_broken)
		limb_system.limb_healed.connect(_on_limb_healed)
	
	# 连接部位UI信号
	if player_limb_ui:
		player_limb_ui.limb_selected.connect(_on_player_limb_selected)
		player_limb_ui.heal_requested.connect(_on_heal_requested)
		player_limb_ui.detail_requested.connect(_on_limb_detail_requested)
	
	if enemy_limb_ui:
		enemy_limb_ui.limb_selected.connect(_on_enemy_limb_selected)
		enemy_limb_ui.detail_requested.connect(_on_enemy_limb_detail_requested)
	
	# 连接动作按钮
	if attack_btn:
		attack_btn.pressed.connect(_on_attack_pressed)
	if defend_btn:
		defend_btn.pressed.connect(_on_defend_pressed)
	if item_btn:
		item_btn.pressed.connect(_on_item_pressed)
	if flee_btn:
		flee_btn.pressed.connect(_on_flee_pressed)
	
	# 连接部位选择按钮
	for limb in limb_buttons:
		var btn = limb_buttons[limb]
		if btn:
			btn.pressed.connect(_on_limb_button_pressed.bind(limb))
	
	if cancel_target_btn:
		cancel_target_btn.pressed.connect(_on_cancel_targeting)

# ========== UI更新 ==========
func _update_limb_button_labels() -> void:
	if not limb_system:
		return
	
	for limb in limb_buttons:
		var btn = limb_buttons[limb]
		if btn:
			var limb_data = limb_system.get_limb_state(limb, false)
			var limb_name = limb_system.get_limb_name(limb)
			var hp_text = "[%d/%d]" % [limb_data.hp, limb_data.max_hp]
			btn.text = "%s %s" % [limb_name, hp_text]
			
			# 根据状态设置可用性
			var is_functional = limb_system.is_limb_functional(limb, false)
			btn.disabled = not is_functional
			
			# 根据状态设置颜色
			match limb_data.state:
				LimbDamageSystem.LimbState.NORMAL:
					btn.modulate = Color(1, 1, 1)
				LimbDamageSystem.LimbState.DAMAGED:
					btn.modulate = Color(1, 0.7, 0.3)
				LimbDamageSystem.LimbState.BROKEN:
					btn.modulate = Color(0.5, 0.5, 0.5)

func _update_action_buttons(enabled: bool) -> void:
	if attack_btn:
		attack_btn.disabled = not enabled
	if defend_btn:
		defend_btn.disabled = not enabled
	if item_btn:
		item_btn.disabled = not enabled
	if flee_btn:
		flee_btn.disabled = not enabled

# ========== 部位选择UI ==========
func _show_limb_selection(attack_type: String = "normal") -> void:
	is_selecting_limb = true
	selected_attack_type = attack_type
	pending_action = "attack"
	
	if limb_selection_panel:
		limb_selection_panel.visible = true
	
	_update_limb_button_labels()
	_update_action_buttons(false)
	
	# 高亮敌人部位UI
	if enemy_limb_ui:
		enemy_limb_ui.set_interactive(true)
	
	limb_targeting_started.emit()
	_add_log_message("选择要攻击的部位...", "system")

func _hide_limb_selection() -> void:
	is_selecting_limb = false
	selected_attack_type = ""
	pending_action = ""
	
	if limb_selection_panel:
		limb_selection_panel.visible = false
	
	_update_action_buttons(true)
	
	# 禁用敌人部位UI的交互
	if enemy_limb_ui:
		enemy_limb_ui.set_interactive(false)
		enemy_limb_ui.clear_selection()
	
	limb_targeting_cancelled.emit()

func _execute_limb_attack(limb: int) -> void:
	if not combat_system:
		return
	
	_hide_limb_selection()
	
	match selected_attack_type:
		"heavy":
			if combat_module:
				combat_module.perform_heavy_attack(limb)
			else:
				combat_system.perform_attack(limb)
		"quick":
			if combat_module:
				combat_module.perform_quick_attack(limb)
			else:
				combat_system.perform_attack(limb)
		_:
			combat_system.perform_limb_attack(limb)
	
	attack_initiated.emit(limb, selected_attack_type)

# ========== 按钮处理 ==========
func _on_attack_pressed() -> void:
	if show_limb_selection:
		_show_limb_selection("normal")
	else:
		# 自动选择
		var target = LimbDamageSystem.LimbType.TORSO
		if limb_system and auto_target_functional:
			target = limb_system.get_random_functional_limb(false)
		combat_system.perform_attack(target)

func _on_defend_pressed() -> void:
	if combat_system:
		combat_system.perform_defend()
	defend_initiated.emit()

func _on_item_pressed() -> void:
	item_menu_requested.emit()

func _on_flee_pressed() -> void:
	if combat_system:
		combat_system.perform_flee()
	flee_requested.emit()

func _on_limb_button_pressed(limb: int) -> void:
	_execute_limb_attack(limb)

func _on_cancel_targeting() -> void:
	_hide_limb_selection()
	_add_log_message("取消攻击", "system")

# ========== 部位选择处理 ==========
func _on_enemy_limb_selected(limb: int) -> void:
	if is_selecting_limb:
		_execute_limb_attack(limb)

func _on_player_limb_selected(limb: int) -> void:
	# 玩家部位选择（用于查看详情或自我治疗）
	pass

func _on_heal_requested(limb: int) -> void:
	_add_log_message("请选择治疗物品...", "system")
	# 这里应该打开物品菜单并筛选治疗物品

func _on_limb_detail_requested(limb: int) -> void:
	if not limb_system:
		return
	
	var desc = limb_system.get_limb_description(limb)
	var effect = limb_system.get_limb_current_effect(limb, true)
	
	# 显示详情弹窗
	_show_detail_popup(limb_system.get_limb_name(limb), desc + "\n\n当前: " + effect)

func _on_enemy_limb_detail_requested(limb: int) -> void:
	if not limb_system:
		return
	
	var desc = limb_system.get_limb_description(limb)
	var state = limb_system.get_limb_state(limb, false)
	var status = "未知"
	
	match state.state:
		LimbDamageSystem.LimbState.NORMAL:
			status = "看起来完好"
		LimbDamageSystem.LimbState.DAMAGED:
			status = "看起来受伤了"
		LimbDamageSystem.LimbState.BROKEN:
			status = "看起来严重受损"
	
	_show_detail_popup(limb_system.get_limb_name(limb), desc + "\n\n观察: " + status)

func _show_detail_popup(title: String, content: String) -> void:
	# 创建详情弹窗
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = content
	dialog.min_size = Vector2(300, 200)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)

# ========== 战斗事件处理 ==========
func _on_combat_started(enemy_data: Dictionary) -> void:
	visible = true
	_update_action_buttons(true)
	
	# 更新敌人信息显示
	if enemy_info and enemy_data.has("name"):
		var name_label = enemy_info.get_node_or_null("NameLabel")
		if name_label:
			name_label.text = enemy_data.name
	
	# 刷新部位显示
	if player_limb_ui:
		player_limb_ui.refresh_display()
	if enemy_limb_ui:
		enemy_limb_ui.refresh_display()
	
	_add_log_message("遭遇 %s！" % enemy_data.get("name", "敌人"), "system")

func _on_combat_ended(victory: bool) -> void:
	_update_action_buttons(false)
	
	if victory:
		_add_log_message("战斗胜利！", "victory")
	else:
		_add_log_message("战斗结束", "system")
	
	# 延迟隐藏UI
	await get_tree().create_timer(2.0).timeout
	visible = false

func _on_turn_started(is_player_turn: bool) -> void:
	_update_action_buttons(is_player_turn)
	
	if is_player_turn:
		_add_log_message("你的回合", "turn")
		
		# 检查部位状态并提示
		_check_limb_status_warnings()
	else:
		_add_log_message("敌人回合", "turn")

func _on_action_performed(action: String, result: Dictionary) -> void:
	# 刷新部位显示
	if enemy_limb_ui:
		enemy_limb_ui.refresh_display()

func _on_damage_dealt(damage: int, is_critical: bool, target_limb: int) -> void:
	# 伤害显示动画
	if enemy_limb_ui:
		enemy_limb_ui.select_limb(target_limb)
		await get_tree().create_timer(0.5).timeout
		enemy_limb_ui.clear_selection()

func _on_damage_taken(damage: int, attacker_limb: int) -> void:
	# 受到伤害动画
	if player_limb_ui:
		player_limb_ui.select_limb(attacker_limb)
		await get_tree().create_timer(0.5).timeout
		player_limb_ui.clear_selection()

func _on_limb_target_selected(limb: int) -> void:
	# 目标部位已选择
	pass

func _on_limb_damaged(limb: int, state: int, is_player: bool) -> void:
	if is_player:
		if player_limb_ui:
			player_limb_ui.refresh_display()
	else:
		if enemy_limb_ui:
			enemy_limb_ui.refresh_display()
		# 更新部位选择按钮
		_update_limb_button_labels()

func _on_limb_broken(limb: int, is_player: bool) -> void:
	var limb_name = limb_system.get_limb_name(limb) if limb_system else "部位"
	var target = "你的" if is_player else "敌人的"
	_add_log_message("%s%s被彻底破坏！" % [target, limb_name], "critical")
	
	if is_player and player_limb_ui:
		player_limb_ui.refresh_display()
	elif not is_player and enemy_limb_ui:
		enemy_limb_ui.refresh_display()
	
	_update_limb_button_labels()

func _on_limb_healed(limb: int, amount: int, is_player: bool) -> void:
	if is_player and player_limb_ui:
		player_limb_ui.refresh_display()

func _on_combat_log_message(message: String, type: String) -> void:
	_add_log_message(message, type)

# ========== 日志系统 ==========
func _add_log_message(message: String, type: String = "normal") -> void:
	if not combat_log:
		return
	
	var color = "white"
	match type:
		"system":
			color = "gray"
		"damage":
			color = "orange"
		"critical":
			color = "red"
		"heal":
			color = "green"
		"victory":
			color = "yellow"
		"defeat":
			color = "darkred"
		"turn":
			color = "cyan"
		"limb_damage":
			color = "coral"
		"limb_broken":
			color = "crimson"
		"effect":
			color = "plum"
		"buff":
			color = "lightgreen"
		"warning":
			color = "gold"
		"reward":
			color = "lime"
	
	var timestamp = ""
	if combat_system:
		timestamp = "[Turn %d] " % combat_system.current_turn
	
	var formatted = "[color=%s]%s%s[/color]\n" % [color, timestamp, message]
	combat_log.append_text(formatted)
	
	# 自动滚动到底部
	combat_log.scroll_to_line(combat_log.get_line_count())

func _check_limb_status_warnings() -> void:
	if not limb_system:
		return
	
	var critical_limbs = []
	for limb in LimbDamageSystem.LimbType.values():
		var state = limb_system.get_limb_state(limb, true)
		if state.state == LimbDamageSystem.LimbState.BROKEN:
			critical_limbs.append(limb_system.get_limb_name(limb))
		elif state.state == LimbDamageSystem.LimbState.DAMAGED and state.hp <= state.max_hp * 0.15:
			critical_limbs.append(limb_system.get_limb_name(limb) + "(危急)")
	
	if not critical_limbs.is_empty():
		var warning = "警告：" + ", ".join(critical_limbs) + "需要治疗！"
		_add_log_message(warning, "warning")

# ========== 公共方法 ==========
## 显示治疗选择UI
func show_heal_selection() -> void:
	if player_limb_ui:
		player_limb_ui.set_heal_available(true)

## 隐藏治疗选择UI
func hide_heal_selection() -> void:
	if player_limb_ui:
		player_limb_ui.set_heal_available(false)

## 添加自定义日志
func add_log(message: String, type: String = "normal") -> void:
	_add_log_message(message, type)

## 获取部位UI引用
func get_player_limb_ui() -> LimbStatusUI:
	return player_limb_ui

func get_enemy_limb_ui() -> LimbStatusUI:
	return enemy_limb_ui

## 强制刷新显示
func force_refresh() -> void:
	if player_limb_ui:
		player_limb_ui.refresh_display()
	if enemy_limb_ui:
		enemy_limb_ui.refresh_display()
	_update_limb_button_labels()
