extends Control
## 部位状态UI - 显示角色5个部位的状态
## 支持玩家和敌人的部位显示

class_name LimbStatusUI

# ========== 信号 ==========
signal limb_selected(limb: int)
signal heal_requested(limb: int)
signal detail_requested(limb: int)

# ========== 导出变量 ==========
@export var is_player_ui: bool = true  # true=玩家UI, false=敌人UI
@export var show_heal_buttons: bool = true
@export var interactive: bool = true
@export var compact_mode: bool = false

# ========== 节点引用 ==========
@onready var limbs_container: VBoxContainer = $LimbsContainer
@onready var title_label: Label = $TitleLabel
@onready var total_hp_bar: ProgressBar = $TotalHPBar

# ========== 预制件 ==========
var limb_panel_scene: PackedScene = preload("res://ui/limb_panel.tscn") if ResourceLoader.exists("res://ui/limb_panel.tscn") else null

# ========== 颜色配置 ==========
var colors: Dictionary = {
	"normal": Color(0.2, 0.8, 0.2),      # 绿色 - 正常
	"damaged": Color(0.9, 0.6, 0.1),     # 橙色 - 受损
	"broken": Color(0.9, 0.2, 0.2),      # 红色 - 损坏
	"background": Color(0.1, 0.1, 0.1, 0.8),
	"text_normal": Color(1, 1, 1),
	"text_damaged": Color(1, 0.8, 0.5),
	"text_broken": Color(1, 0.5, 0.5)
}

# ========== 状态变量 ==========
var limb_system: LimbDamageSystem = null
var limb_panels: Dictionary = {}
var current_limbs_state: Dictionary = {}

# 部位图标（可以使用Texture2D或Unicode字符）
var limb_icons: Dictionary = {
	LimbDamageSystem.LimbType.HEAD: "🧠",
	LimbDamageSystem.LimbType.TORSO: "🛡️",
	LimbDamageSystem.LimbType.LEFT_ARM: "💪",
	LimbDamageSystem.LimbType.RIGHT_ARM: "🦾",
	LimbDamageSystem.LimbType.LEGS: "🦵"
}

# ========== 初始化 ==========
func _ready():
	_initialize_systems()
	_setup_ui()
	_connect_signals()
	refresh_display()

func _initialize_systems() -> void:
	if Engine.has_singleton("LimbDamageSystem"):
		limb_system = Engine.get_singleton("LimbDamageSystem")
	elif has_node("/root/LimbDamageSystem"):
		limb_system = get_node("/root/LimbDamageSystem")

func _setup_ui() -> void:
	# 设置标题
	if title_label:
		title_label.text = "部位状态" if is_player_ui else "敌人部位"
	
	# 创建部位面板
	_create_limb_panels()
	
	# 设置总HP条
	if total_hp_bar:
		total_hp_bar.min_value = 0

func _create_limb_panels() -> void:
	if not limbs_container:
		return
	
	# 清除现有子节点
	for child in limbs_container.get_children():
		child.queue_free()
	limb_panels.clear()
	
	# 创建5个部位的面板
	var limb_order = [
		LimbDamageSystem.LimbType.HEAD,
		LimbDamageSystem.LimbType.TORSO,
		LimbDamageSystem.LimbType.LEFT_ARM,
		LimbDamageSystem.LimbType.RIGHT_ARM,
		LimbDamageSystem.LimbType.LEGS
	]
	
	for limb in limb_order:
		var panel = _create_limb_panel(limb)
		limbs_container.add_child(panel)
		limb_panels[limb] = panel

func _create_limb_panel(limb: int) -> Control:
	if limb_panel_scene:
		var panel = limb_panel_scene.instantiate()
		_setup_panel_content(panel, limb)
		return panel
	else:
		# 动态创建面板
		return _build_limb_panel(limb)

func _build_limb_panel(limb: int) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 40 if compact_mode else 60)
	
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)
	
	# 图标
	var icon_label = Label.new()
	icon_label.text = limb_icons.get(limb, "•")
	icon_label.add_theme_font_size_override("font_size", 20 if compact_mode else 28)
	icon_label.custom_minimum_size = Vector2(40, 40)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon_label)
	
	# 信息容器
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	# 名称行
	var name_hbox = HBoxContainer.new()
	vbox.add_child(name_hbox)
	
	var name_label = Label.new()
	name_label.text = _get_limb_name(limb)
	name_label.add_theme_font_size_override("font_size", 12 if compact_mode else 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(name_label)
	
	# 状态标签
	var status_label = Label.new()
	status_label.text = "正常"
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 10 if compact_mode else 12)
	name_hbox.add_child(status_label)
	
	# HP条
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.custom_minimum_size = Vector2(0, 8 if compact_mode else 12)
	if compact_mode:
		hp_bar.add_theme_stylebox_override("fill", _create_compact_fill_style())
	vbox.add_child(hp_bar)
	
	# HP数值
	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = "100/100"
	hp_label.add_theme_font_size_override("font_size", 10 if compact_mode else 11)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(hp_label)
	
	# 治疗按钮（仅玩家UI）
	if show_heal_buttons and is_player_ui:
		var heal_btn = Button.new()
		heal_btn.name = "HealButton"
		heal_btn.text = "+"
		heal_btn.tooltip_text = "治疗该部位"
		heal_btn.custom_minimum_size = Vector2(32, 32)
		heal_btn.visible = false  # 默认隐藏，有治疗物品时显示
		heal_btn.pressed.connect(_on_heal_button_pressed.bind(limb))
		hbox.add_child(heal_btn)
	
	# 交互
	if interactive:
		panel.gui_input.connect(_on_panel_input.bind(limb))
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	return panel

func _setup_panel_content(panel: Control, limb: int) -> void:
	# 设置预制件面板的内容
	if panel.has_node("Icon"):
		panel.get_node("Icon").text = limb_icons.get(limb, "•")
	if panel.has_node("Name"):
		panel.get_node("Name").text = _get_limb_name(limb)

func _create_compact_fill_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = colors.normal
	return style

func _connect_signals() -> void:
	if limb_system:
		limb_system.all_limbs_updated.connect(_on_limbs_updated)
		limb_system.limb_damaged.connect(_on_limb_damaged)
		limb_system.limb_healed.connect(_on_limb_healed)
		limb_system.limb_broken.connect(_on_limb_broken)

# ========== 显示更新 ==========
## 刷新显示
func refresh_display() -> void:
	if not limb_system:
		return
	
	var limbs_state = limb_system.get_all_limbs_state(is_player_ui)
	current_limbs_state = limbs_state
	
	var total_hp = 0
	var total_max = 0
	
	for limb in limbs_state:
		var state = limbs_state[limb]
		total_hp += state.hp
		total_max += state.max_hp
		_update_limb_display(limb, state)
	
	# 更新总HP
	if total_hp_bar:
		total_hp_bar.max_value = total_max
		total_hp_bar.value = total_hp
		total_hp_bar.tooltip_text = "总HP: %d/%d" % [total_hp, total_max]

func _update_limb_display(limb: int, state: Dictionary) -> void:
	if not limb_panels.has(limb):
		return
	
	var panel = limb_panels[limb]
	var hp_percent = float(state.hp) / state.max_hp
	
	# 更新HP条
	var hp_bar = panel.get_node_or_null("HPBar")
	if hp_bar:
		hp_bar.max_value = state.max_hp
		hp_bar.value = state.hp
		
		# 根据状态设置颜色
		var bar_color = colors.normal
		match state.state:
			LimbDamageSystem.LimbState.DAMAGED:
				bar_color = colors.damaged
			LimbDamageSystem.LimbState.BROKEN:
				bar_color = colors.broken
		
		if hp_bar.has_theme_stylebox_override("fill"):
			var style = hp_bar.get_theme_stylebox("fill").duplicate()
			if style is StyleBoxFlat:
				style.bg_color = bar_color
				hp_bar.add_theme_stylebox_override("fill", style)
	
	# 更新HP数值
	var hp_label = panel.get_node_or_null("HPLabel")
	if hp_label:
		hp_label.text = "%d/%d" % [state.hp, state.max_hp]
		
		# 根据状态设置文字颜色
		match state.state:
			LimbDamageSystem.LimbState.NORMAL:
				hp_label.add_theme_color_override("font_color", colors.text_normal)
			LimbDamageSystem.LimbState.DAMAGED:
				hp_label.add_theme_color_override("font_color", colors.text_damaged)
			LimbDamageSystem.LimbState.BROKEN:
				hp_label.add_theme_color_override("font_color", colors.text_broken)
	
	# 更新状态标签
	var status_label = panel.get_node_or_null("StatusLabel")
	if status_label:
		status_label.text = _get_state_name(state.state)
		match state.state:
			LimbDamageSystem.LimbState.NORMAL:
				status_label.add_theme_color_override("font_color", colors.normal)
			LimbDamageSystem.LimbState.DAMAGED:
				status_label.add_theme_color_override("font_color", colors.damaged)
			LimbDamageSystem.LimbState.BROKEN:
				status_label.add_theme_color_override("font_color", colors.broken)
	
	# 更新治疗按钮可见性
	if show_heal_buttons and is_player_ui:
		var heal_btn = panel.get_node_or_null("HealButton")
		if heal_btn:
			heal_btn.visible = state.state != LimbDamageSystem.LimbState.NORMAL
			heal_btn.disabled = state.state == LimbDamageSystem.LimbState.NORMAL

# ========== 事件处理 ==========
func _on_limbs_updated(_player_limbs: Dictionary, _enemy_limbs: Dictionary) -> void:
	refresh_display()

func _on_limb_damaged(limb: int, state: int, is_player: bool) -> void:
	if is_player == is_player_ui:
		# 播放受损动画或效果
		_flash_limb_panel(limb, colors.damaged)

func _on_limb_healed(limb: int, _amount: int, is_player: bool) -> void:
	if is_player == is_player_ui:
		# 播放治疗动画
		_flash_limb_panel(limb, colors.normal)

func _on_limb_broken(limb: int, is_player: bool) -> void:
	if is_player == is_player_ui:
		# 播放损坏动画
		_flash_limb_panel(limb, colors.broken)
		_shake_panel(limb)

func _on_panel_input(event: InputEvent, limb: int) -> void:
	if not interactive:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			limb_selected.emit(limb)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			detail_requested.emit(limb)
	elif event is InputEventMouseMotion:
		# 显示提示
		_show_limb_tooltip(limb)

func _on_heal_button_pressed(limb: int) -> void:
	heal_requested.emit(limb)

# ========== 动画效果 ==========
func _flash_limb_panel(limb: int, flash_color: Color) -> void:
	if not limb_panels.has(limb):
		return
	
	var panel = limb_panels[limb]
	var original_modulate = panel.modulate
	
	# 闪烁效果
	var tween = create_tween()
	tween.tween_property(panel, "modulate", flash_color, 0.1)
	tween.tween_property(panel, "modulate", original_modulate, 0.3)

func _shake_panel(limb: int) -> void:
	if not limb_panels.has(limb):
		return
	
	var panel = limb_panels[limb]
	var original_pos = panel.position
	
	# 震动效果
	var tween = create_tween()
	for i in range(5):
		var offset = Vector2(randf_range(-3, 3), randf_range(-3, 3))
		tween.tween_property(panel, "position", original_pos + offset, 0.05)
	tween.tween_property(panel, "position", original_pos, 0.1)

func _show_limb_tooltip(limb: int) -> void:
	if not limb_system:
		return
	
	var desc = limb_system.get_limb_description(limb)
	var current_effect = limb_system.get_limb_current_effect(limb, is_player_ui)
	
	var tooltip = desc + "\n\n当前效果: " + current_effect
	
	if limb_panels.has(limb):
		limb_panels[limb].tooltip_text = tooltip

# ========== 公共方法 ==========
## 选择部位（高亮显示）
func select_limb(limb: int) -> void:
	for l in limb_panels:
		var panel = limb_panels[l]
		if l == limb:
			panel.modulate = Color(1.2, 1.2, 1.2)  # 高亮
		else:
			panel.modulate = Color(1, 1, 1)  # 正常

## 清除选择
func clear_selection() -> void:
	for panel in limb_panels.values():
		panel.modulate = Color(1, 1, 1)

## 显示治疗可用性
func set_heal_available(available: bool) -> void:
	if not show_heal_buttons or not is_player_ui:
		return
	
	for limb in limb_panels:
		var panel = limb_panels[limb]
		var heal_btn = panel.get_node_or_null("HealButton")
		if heal_btn:
			var state = current_limbs_state.get(limb, {})
			var limb_state = state.get("state", LimbDamageSystem.LimbState.NORMAL)
			heal_btn.visible = available and limb_state != LimbDamageSystem.LimbState.NORMAL

## 设置交互状态
func set_interactive(enabled: bool) -> void:
	interactive = enabled
	for panel in limb_panels.values():
		if enabled:
			panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			panel.mouse_default_cursor_shape = Control.CURSOR_ARROW

# ========== 辅助方法 ==========
func _get_limb_name(limb: int) -> String:
	if limb_system:
		return limb_system.get_limb_name(limb)
	
	var names = {
		LimbDamageSystem.LimbType.HEAD: "头部",
		LimbDamageSystem.LimbType.TORSO: "躯干",
		LimbDamageSystem.LimbType.LEFT_ARM: "左臂",
		LimbDamageSystem.LimbType.RIGHT_ARM: "右臂",
		LimbDamageSystem.LimbType.LEGS: "腿部"
	}
	return names.get(limb, "未知")

func _get_state_name(state: int) -> String:
	match state:
		LimbDamageSystem.LimbState.NORMAL:
			return "正常"
		LimbDamageSystem.LimbState.DAMAGED:
			return "受损"
		LimbDamageSystem.LimbState.BROKEN:
			return "损坏"
	return "未知"

# ========== 快捷创建方法 ==========
## 创建玩家UI
static func create_player_ui() -> LimbStatusUI:
	var ui = LimbStatusUI.new()
	ui.is_player_ui = true
	ui.show_heal_buttons = true
	ui.interactive = true
	return ui

## 创建敌人UI
static func create_enemy_ui() -> LimbStatusUI:
	var ui = LimbStatusUI.new()
	ui.is_player_ui = false
	ui.show_heal_buttons = false
	ui.interactive = false
	return ui
