extends Control
# WebLoadingScreen - Web版本加载进度屏幕

@onready var progress_bar = $CenterContainer/VBoxContainer/ProgressBar
@onready var status_label = $CenterContainer/VBoxContainer/StatusLabel
@onready var subtitle_label = $CenterContainer/VBoxContainer/SubtitleLabel

var _loading_progress: float = 0.0
var _target_progress: float = 0.0
var _loading_complete: bool = false

const TIPS = [
	"提示：收集资源，制作工具，在末日中生存下去！",
	"提示：保持饥饿值和口渴值，否则健康会持续下降。",
	"提示：白天外出探索相对安全，夜晚风险会大幅增加。",
	"提示：合理分配负重，超载会影响移动速度。",
	"提示：在安全屋可以休息恢复体力和精神状态。",
	"提示：制作武器可以提升战斗能力。",
	"提示：注意关注角色的HP、饥饿、口渴等状态。"
]

func _ready():
	# 随机显示一条提示
	var random_tip = TIPS[randi() % TIPS.size()]
	$CenterContainer/VBoxContainer/TipLabel.text = random_tip
	
	# 检查是否为移动设备并调整UI
	if ResponsiveUIManager:
		if ResponsiveUIManager.is_mobile():
			_adjust_for_mobile()
	
	# 开始加载进度模拟
	_start_loading()

func _process(delta):
	# 平滑更新进度条
	if _loading_progress < _target_progress:
		_loading_progress = lerp(_loading_progress, _target_progress, delta * 3.0)
		progress_bar.value = _loading_progress
	
	# 检查加载完成
	if _loading_progress >= 99.0 and not _loading_complete:
		_on_loading_complete()

func _start_loading():
	progress_bar.value = 0.0
	status_label.text = "正在初始化游戏引擎..."
	
	# 模拟加载阶段
	await get_tree().create_timer(0.5).timeout
	_update_progress(20.0, "正在加载游戏资源...")
	
	await get_tree().create_timer(0.8).timeout
	_update_progress(45.0, "正在加载纹理和音效...")
	
	await get_tree().create_timer(0.6).timeout
	_update_progress(70.0, "正在初始化游戏系统...")
	
	await get_tree().create_timer(0.5).timeout
	_update_progress(90.0, "正在准备游戏场景...")
	
	await get_tree().create_timer(0.5).timeout
	_update_progress(100.0, "加载完成！")

func _update_progress(progress: float, status: String):
	_target_progress = progress
	status_label.text = status

func _on_loading_complete():
	_loading_complete = true
	subtitle_label.text = "点击屏幕开始游戏"
	status_label.text = "加载完成"
	
	# 等待用户点击（触摸或鼠标）
	set_process_input(true)

func _input(event):
	if _loading_complete and (event is InputEventScreenTouch or event is InputEventMouseButton):
		if (event is InputEventScreenTouch and event.pressed) or \
		   (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_start_game()

func _start_game():
	# 切换到主菜单
	set_process_input(false)
	
	# 淡出效果
	var tween = create_tween()
	modulate = Color(1, 1, 1, 1)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.5)
	await tween.finished
	
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _adjust_for_mobile():
	# 移动端调整字体大小
	var title_label = $CenterContainer/VBoxContainer/TitleLabel
	var status_label_node = $CenterContainer/VBoxContainer/StatusLabel
	var tip_label = $CenterContainer/VBoxContainer/TipLabel
	
	title_label.add_theme_font_size_override("font_size", ResponsiveUIManager.get_font_size(32))
	status_label_node.add_theme_font_size_override("font_size", ResponsiveUIManager.get_font_size(16))
	tip_label.add_theme_font_size_override("font_size", ResponsiveUIManager.get_font_size(14))
	
	# 增大进度条
	progress_bar.custom_minimum_size = Vector2(280, 36)
