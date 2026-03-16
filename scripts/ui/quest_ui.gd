extends CanvasLayer
# QuestUI - 任务界面
const InputActions = preload("res://core/input_actions.gd")

@onready var quest_panel = $QuestPanel
@onready var quest_list = $QuestPanel/VBoxContainer/QuestList
@onready var toggle_button = $ToggleButton
@onready var animation_player = $AnimationPlayer

var is_visible = false

func _ready():
	toggle_button.pressed.connect(_on_toggle_pressed)
	quest_panel.visible = false
	
	# 订阅任务事件
	QuestSystem.quest_started.connect(_on_quest_started)
	QuestSystem.quest_updated.connect(_on_quest_updated)
	QuestSystem.quest_completed.connect(_on_quest_completed)
	
	_update_quest_display()

func _on_toggle_pressed():
	if is_visible:
		_hide_panel()
	else:
		_show_panel()

func _show_panel():
	is_visible = true
	quest_panel.visible = true
	_update_quest_display()
	animation_player.play("show")

func _hide_panel():
	is_visible = false
	animation_player.play("hide")
	await animation_player.animation_finished
	quest_panel.visible = false

func _update_quest_display():
	# 清除现有列表
	for child in quest_list.get_children():
		child.queue_free()
	
	# 获取当前任务
	var active_quests = QuestSystem.get_active_quests()
	
	if active_quests.size() == 0:
		var label = Label.new()
		label.text = "当前没有进行中的任务"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quest_list.add_child(label)
	else:
		for quest in active_quests:
			_add_quest_item(quest)

func _add_quest_item(quest: Dictionary):
	var item = PanelContainer.new()
	item.custom_minimum_size = Vector2(0, 80)
	
	var vbox = VBoxContainer.new()
	item.add_child(vbox)
	
	# 任务标题
	var title_label = Label.new()
	title_label.text = quest.get("title", "未知任务")
	title_label.theme_type_variation = "HeaderSmall"
	vbox.add_child(title_label)
	
	# 任务描述
	var desc = Label.new()
	desc.text = quest.get("description", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)
	
	# 进度
	var progress = quest.get("progress", {})
	for obj_id in progress.keys():
		var obj = progress[obj_id]
		var progress_label = Label.new()
		progress_label.text = "  %s: %s/%s" % [
			obj.get("description", ""),
			obj.get("current", 0),
			obj.get("target", 0)
		]
		progress_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(progress_label)
	
	quest_list.add_child(item)
	
	# 添加分隔线
	var separator = HSeparator.new()
	quest_list.add_child(separator)

func _on_quest_started(quest_id: String):
	var quest = QuestSystem.get_quest_template(quest_id) if QuestSystem.has_method("get_quest_template") else QuestSystem.QUESTS.get(quest_id, {})
	_show_notification("新任务", quest.get("title", "未知任务"))
	if is_visible:
		_update_quest_display()

func _on_quest_updated(quest_id: String, _progress: Dictionary = {}):
	if is_visible:
		_update_quest_display()

func _on_quest_completed(quest_id: String, _rewards: Dictionary = {}):
	var quest = QuestSystem.get_quest_template(quest_id) if QuestSystem.has_method("get_quest_template") else QuestSystem.QUESTS.get(quest_id, {})
	_show_notification("任务完成", quest.get("title", "未知任务"))
	if is_visible:
		_update_quest_display()

func _show_notification(title: String, message: String):
	var notification = PanelContainer.new()
	notification.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	notification.position = Vector2(get_viewport().size.x - 300, 100)
	
	var vbox = VBoxContainer.new()
	notification.add_child(vbox)
	
	var title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	
	var msg_label = Label.new()
	msg_label.text = message
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg_label)
	
	add_child(notification)
	
	# 自动消失
	await get_tree().create_timer(3.0).timeout
	notification.queue_free()

func _input(event: InputEvent):
	if event.is_action_pressed(InputActions.ACTION_MENU_JOURNAL):
		_on_toggle_pressed()
