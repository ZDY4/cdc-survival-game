@tool
extends EditorPlugin

const PLUGIN_NAME = "CDC Game Editor"
const PLUGIN_VERSION = "2.1.0"

# 编辑器实例
var dialog_editor: Control = null
var quest_editor: Control = null
var item_editor: Control = null
var npc_editor: Control = null
var recipe_editor: Control = null

# UI 元素
var dialog_button: Button
var quest_button: Button
var item_button: Button
var npc_button: Button
var recipe_button: Button
var toolbar_separator: VSeparator

# 当前激活的编辑器
var current_editor: String = ""

func _enter_tree():
	print("[%s v%s] 正在初始化..." % [PLUGIN_NAME, PLUGIN_VERSION])
	
	# 创建工具栏按钮
	_create_toolbar_buttons()
	
	# 创建编辑器面板
	_create_editor_panels()
	
	print("[%s] 初始化完成" % PLUGIN_NAME)

func _exit_tree():
	# 移除工具栏按钮
	if dialog_button:
		remove_control_from_container(CONTAINER_TOOLBAR, dialog_button)
		dialog_button.queue_free()
		dialog_button = null
	
	if quest_button:
		remove_control_from_container(CONTAINER_TOOLBAR, quest_button)
		quest_button.queue_free()
		quest_button = null
	
	if item_button:
		remove_control_from_container(CONTAINER_TOOLBAR, item_button)
		item_button.queue_free()
		item_button = null
	
	if npc_button:
		remove_control_from_container(CONTAINER_TOOLBAR, npc_button)
		npc_button.queue_free()
		npc_button = null
	
	if recipe_button:
		remove_control_from_container(CONTAINER_TOOLBAR, recipe_button)
		recipe_button.queue_free()
		recipe_button = null
	
	if toolbar_separator:
		remove_control_from_container(CONTAINER_TOOLBAR, toolbar_separator)
		toolbar_separator.queue_free()
		toolbar_separator = null
	
	# 移除编辑器面板
	if dialog_editor:
		dialog_editor.queue_free()
		dialog_editor = null
	
	if quest_editor:
		quest_editor.queue_free()
		quest_editor = null
	
	if item_editor:
		item_editor.queue_free()
		item_editor = null
	
	if npc_editor:
		npc_editor.queue_free()
		npc_editor = null
	
	if recipe_editor:
		recipe_editor.queue_free()
		recipe_editor = null
	
	print("[%s] 已禁用" % PLUGIN_NAME)

func _create_toolbar_buttons():
	toolbar_separator = VSeparator.new()
	add_control_to_container(CONTAINER_TOOLBAR, toolbar_separator)
	
	dialog_button = Button.new()
	dialog_button.text = "📝 对话编辑器"
	dialog_button.tooltip_text = "打开对话编辑器 (Ctrl+Shift+D)"
	dialog_button.pressed.connect(_on_dialog_button_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, dialog_button)
	
	quest_button = Button.new()
	quest_button.text = "📜 任务编辑器"
	quest_button.tooltip_text = "打开任务编辑器 (Ctrl+Shift+Q)"
	quest_button.pressed.connect(_on_quest_button_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, quest_button)
	
	item_button = Button.new()
	item_button.text = "📦 物品编辑器"
	item_button.tooltip_text = "打开物品编辑器 (Ctrl+Shift+I)"
	item_button.pressed.connect(_on_item_button_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, item_button)
	
	npc_button = Button.new()
	npc_button.text = "🧑 NPC编辑器"
	npc_button.tooltip_text = "打开NPC编辑器 (Ctrl+Shift+N)"
	npc_button.pressed.connect(_on_npc_button_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, npc_button)
	
	recipe_button = Button.new()
	recipe_button.text = "⚗️ 配方编辑器"
	recipe_button.tooltip_text = "打开配方编辑器 (Ctrl+Shift+R)"
	recipe_button.pressed.connect(_on_recipe_button_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, recipe_button)

func _create_editor_panels():
	# 创建对话编辑器
	var dialog_script = load("res://addons/cdc_game_editor/editors/dialog_editor/dialog_editor.gd")
	if dialog_script:
		dialog_editor = dialog_script.new()
		dialog_editor.name = "DialogEditor"
		dialog_editor.editor_plugin = self
		dialog_editor.hide()
		dialog_editor.size = Vector2(1200, 800)
		get_editor_interface().get_editor_main_screen().add_child(dialog_editor)
		print("[%s] 对话编辑器已创建" % PLUGIN_NAME)
	else:
		push_error("[%s] 无法加载对话编辑器脚本" % PLUGIN_NAME)
	
	# 创建任务编辑器
	var quest_script = load("res://addons/cdc_game_editor/editors/quest_editor/quest_editor.gd")
	if quest_script:
		quest_editor = quest_script.new()
		quest_editor.name = "QuestEditor"
		quest_editor.editor_plugin = self
		quest_editor.hide()
		quest_editor.size = Vector2(1200, 800)
		get_editor_interface().get_editor_main_screen().add_child(quest_editor)
		print("[%s] 任务编辑器已创建" % PLUGIN_NAME)
	else:
		push_error("[%s] 无法加载任务编辑器脚本" % PLUGIN_NAME)
	
	# 创建物品编辑器
	var item_script = load("res://addons/cdc_game_editor/editors/item_editor/item_editor.gd")
	if item_script:
		item_editor = item_script.new()
		item_editor.name = "ItemEditor"
		item_editor.editor_plugin = self
		item_editor.hide()
		item_editor.size = Vector2(1200, 800)
		get_editor_interface().get_editor_main_screen().add_child(item_editor)
		print("[%s] 物品编辑器已创建" % PLUGIN_NAME)
	else:
		push_error("[%s] 无法加载物品编辑器脚本" % PLUGIN_NAME)
	
	# 创建NPC编辑器
	var npc_script = load("res://addons/cdc_game_editor/editors/npc_editor/npc_editor.gd")
	if npc_script:
		npc_editor = npc_script.new()
		npc_editor.name = "NPCEditor"
		npc_editor.editor_plugin = self
		npc_editor.hide()
		npc_editor.size = Vector2(1200, 800)
		get_editor_interface().get_editor_main_screen().add_child(npc_editor)
		print("[%s] NPC编辑器已创建" % PLUGIN_NAME)
	else:
		push_error("[%s] 无法加载NPC编辑器脚本" % PLUGIN_NAME)
	
	# 创建配方编辑器
	var recipe_script = load("res://addons/cdc_game_editor/editors/recipe_editor/recipe_editor.gd")
	if recipe_script:
		recipe_editor = recipe_script.new()
		recipe_editor.name = "RecipeEditor"
		recipe_editor.editor_plugin = self
		recipe_editor.hide()
		recipe_editor.size = Vector2(1200, 800)
		get_editor_interface().get_editor_main_screen().add_child(recipe_editor)
		print("[%s] 配方编辑器已创建" % PLUGIN_NAME)
	else:
		push_error("[%s] 无法加载配方编辑器脚本" % PLUGIN_NAME)

func _on_dialog_button_pressed():
	_show_editor("dialog")

func _on_quest_button_pressed():
	_show_editor("quest")

func _on_item_button_pressed():
	_show_editor("item")

func _on_npc_button_pressed():
	_show_editor("npc")

func _on_recipe_button_pressed():
	_show_editor("recipe")

func _show_editor(editor_type: String):
	current_editor = editor_type
	
	# 隐藏所有编辑器
	if dialog_editor:
		dialog_editor.hide()
	if quest_editor:
		quest_editor.hide()
	if item_editor:
		item_editor.hide()
	if npc_editor:
		npc_editor.hide()
	if recipe_editor:
		recipe_editor.hide()
	
	# 显示选中的编辑器
	match editor_type:
		"dialog":
			if dialog_editor:
				dialog_editor.show()
				dialog_editor.grab_focus()
			_update_button_states(true, false, false, false)
		
		"quest":
			if quest_editor:
				quest_editor.show()
				quest_editor.grab_focus()
			_update_button_states(false, true, false, false)
		
		"item":
			if item_editor:
				item_editor.show()
				item_editor.grab_focus()
			_update_button_states(false, false, true, false)
		
		"npc":
			if npc_editor:
				npc_editor.show()
				npc_editor.grab_focus()
			_update_button_states(false, false, false, true, false)
		
		"recipe":
			if recipe_editor:
				recipe_editor.show()
				recipe_editor.grab_focus()
			_update_button_states(false, false, false, false, true)
	
	# 强制刷新编辑器界面
	get_editor_interface().set_main_screen_editor("Script")
	get_editor_interface().set_main_screen_editor("2D")

func _update_button_states(dialog_active: bool, quest_active: bool, item_active: bool = false, npc_active: bool = false, recipe_active: bool = false):
	if dialog_button:
		dialog_button.modulate = Color(0.8, 1.0, 0.8) if dialog_active else Color.WHITE
	if quest_button:
		quest_button.modulate = Color(0.8, 1.0, 0.8) if quest_active else Color.WHITE
	if item_button:
		item_button.modulate = Color(0.8, 1.0, 0.8) if item_active else Color.WHITE
	if npc_button:
		npc_button.modulate = Color(0.8, 1.0, 0.8) if npc_active else Color.WHITE
	if recipe_button:
		recipe_button.modulate = Color(0.8, 1.0, 0.8) if recipe_active else Color.WHITE

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool):
	if not visible:
		if dialog_editor:
			dialog_editor.hide()
		if quest_editor:
			quest_editor.hide()
		if item_editor:
			item_editor.hide()
		if npc_editor:
			npc_editor.hide()
		if recipe_editor:
			recipe_editor.hide()
		_update_button_states(false, false, false, false, false)
	else:
		# 显示上次激活的编辑器
		match current_editor:
			"dialog":
				if dialog_editor:
					dialog_editor.show()
			"quest":
				if quest_editor:
					quest_editor.show()
			"item":
				if item_editor:
					item_editor.show()
			"npc":
				if npc_editor:
					npc_editor.show()
			"recipe":
				if recipe_editor:
					recipe_editor.show()

func _get_plugin_name() -> String:
	return PLUGIN_NAME

func _get_plugin_icon() -> Texture2D:
	# 使用编辑器内置图标
	return get_editor_interface().get_base_control().get_theme_icon("Edit", "EditorIcons")

func _handles(object: Object) -> bool:
	# 处理各种资源文件
	if object is Resource:
		var path = object.resource_path
		if path.ends_with(".dlg") or path.ends_with(".dialog"):
			return true
		if path.ends_with(".quest") or path.ends_with(".quest_data"):
			return true
		if path.ends_with(".item") or path.ends_with(".items"):
			return true
	return false

func _edit(object: Object):
	if object is Resource:
		var path = object.resource_path
		if path.ends_with(".dlg") or path.ends_with(".dialog"):
			_show_editor("dialog")
		elif path.ends_with(".quest") or path.ends_with(".quest_data"):
			_show_editor("quest")
		elif path.ends_with(".item") or path.ends_with(".items"):
			_show_editor("item")

func _apply_changes() -> bool:
	# 在编辑器失去焦点时检查未保存的更改
	var has_unsaved = false
	if dialog_editor and dialog_editor.has_method("has_unsaved_changes") and dialog_editor.has_unsaved_changes():
		print("[%s] 对话编辑器有未保存的更改" % PLUGIN_NAME)
		has_unsaved = true
	if quest_editor and quest_editor.has_method("has_unsaved_changes") and quest_editor.has_unsaved_changes():
		print("[%s] 任务编辑器有未保存的更改" % PLUGIN_NAME)
		has_unsaved = true
	if item_editor and item_editor.has_method("has_unsaved_changes") and item_editor.has_unsaved_changes():
		print("[%s] 物品编辑器有未保存的更改" % PLUGIN_NAME)
		has_unsaved = true
	if npc_editor and npc_editor.has_method("has_unsaved_changes") and npc_editor.has_unsaved_changes():
		print("[%s] NPC编辑器有未保存的更改" % PLUGIN_NAME)
		has_unsaved = true
	if recipe_editor and recipe_editor.has_method("has_unsaved_changes") and recipe_editor.has_unsaved_changes():
		print("[%s] 配方编辑器有未保存的更改" % PLUGIN_NAME)
		has_unsaved = true
	return true

func _build() -> bool:
	# 在构建项目前验证数据
	var has_errors = false
	
	if quest_editor:
		var errors = quest_editor.get_validation_errors()
		if not errors.is_empty():
			push_warning("[%s] 任务验证发现错误:" % PLUGIN_NAME)
			for quest_id in errors:
				for error in errors[quest_id]:
					push_warning("  - %s: %s" % [quest_id, error])
			has_errors = true
	
	return not has_errors
