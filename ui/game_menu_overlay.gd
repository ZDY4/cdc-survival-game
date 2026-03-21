extends CanvasLayer

const InputActions = preload("res://core/input_actions.gd")
const InventoryGridView = preload("res://ui/inventory_grid_view.gd")
const InventoryEquipmentSlotButton = preload("res://ui/inventory_equipment_slot_button.gd")
const SkillHotbarScript = preload("res://ui/skill_hotbar.gd")
const SkillPanelItemScript = preload("res://ui/skill_panel_item.gd")

signal request_close_all()

var _menu_root: Control = null
var _inventory_panel: PanelContainer = null
var _character_panel: PanelContainer = null
var _journal_panel: PanelContainer = null
var _skills_panel: PanelContainer = null
var _crafting_panel: PanelContainer = null
var _settings_panel: PanelContainer = null
var _world_map: CanvasLayer = null
var _status_label: Label = null
var _skill_hotbar: Control = null

var _inventory_equipment_grid: GridContainer = null
var _inventory_summary_label: Label = null
var _inventory_grid_view: InventoryGridView = null
var _inventory_detail_title: Label = null
var _inventory_detail_meta: Label = null
var _inventory_detail_description: Label = null
var _inventory_action_button: Button = null
var _inventory_organize_button: Button = null
var _inventory_equipment_buttons: Dictionary = {}
var _inventory_equipment_system: Node = null
var _hovered_inventory_instance_id: String = ""
var _selected_inventory_instance_id: String = ""
var _selected_equipment_slot: String = ""
var _character_points_label: Label = null
var _character_strength_label: Label = null
var _character_agility_label: Label = null
var _character_constitution_label: Label = null
var _journal_list: VBoxContainer = null
var _skills_list: GridContainer = null
var _crafting_list: VBoxContainer = null

var _controls_rows: Dictionary = {}
var _pending_rebind_action: StringName = StringName()
var _pending_rebind_label: Label = null
var _rebind_status_label: Label = null
var _panel_contents: Dictionary = {}

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	_build_overlay()
	_hide_all_menus()
	_load_world_map()
	if EventBus and EventBus.has_method("subscribe"):
		EventBus.subscribe(EventBus.EventType.INVENTORY_CHANGED, _on_inventory_event)
	if GameState and GameState.has_signal("equipment_system_ready"):
		GameState.equipment_system_ready.connect(_on_equipment_system_ready)
	_bind_inventory_equipment_system()

func open_menu(action_name: StringName) -> void:
	if action_name == InputActions.ACTION_MENU_MAP:
		if _world_map and _world_map.visible:
			_world_map.call("hide_map")
			return
		_hide_all_panels()
		if _world_map:
			_world_map.call("show_map")
		_status("已打开地图")
		return

	if _is_panel_open(action_name):
		_hide_all_menus()
		return

	_hide_all_menus()
	match action_name:
		InputActions.ACTION_MENU_INVENTORY:
			_refresh_inventory()
			_inventory_panel.show()
		InputActions.ACTION_MENU_CHARACTER:
			_refresh_character()
			_character_panel.show()
		InputActions.ACTION_MENU_JOURNAL:
			_refresh_journal()
			_journal_panel.show()
		InputActions.ACTION_MENU_SKILLS:
			_refresh_skills()
			_skills_panel.show()
		InputActions.ACTION_MENU_CRAFTING:
			_refresh_crafting()
			_crafting_panel.show()
		InputActions.ACTION_MENU_SETTINGS:
			_refresh_controls_tab()
			_settings_panel.show()
		_:
			return
	_status("已打开%s" % InputActions.get_action_label(action_name))

func close_all_menus() -> void:
	_hide_all_menus()

func is_rebinding_input() -> bool:
	return _pending_rebind_action != StringName()

func is_any_menu_open() -> bool:
	return _inventory_panel.visible \
		or _character_panel.visible \
		or _journal_panel.visible \
		or _skills_panel.visible \
		or _crafting_panel.visible \
		or _settings_panel.visible \
		or (_world_map != null and _world_map.visible)

func _input(event: InputEvent) -> void:
	if _pending_rebind_action == StringName():
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var result: Dictionary = ControlSettingsService.set_binding(
		_pending_rebind_action,
		_to_int(key_event.keycode),
		_to_int(key_event.physical_keycode)
	)
	if result.get("success", false):
		_status("已绑定%s: %s" % [
			InputActions.get_action_label(_pending_rebind_action),
			InputActions.keycode_to_text(_to_int(key_event.keycode))
		])
	else:
		_status(str(result.get("reason", "绑定失败")))

	_pending_rebind_action = StringName()
	if _pending_rebind_label:
		_pending_rebind_label.text = ""
		_pending_rebind_label = null
	_refresh_controls_tab()
	get_viewport().set_input_as_handled()

func _to_int(value: Variant, default_value: int = 0) -> int:
	if value == null:
		return default_value

	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			var numeric_value: float = value
			return floori(numeric_value) if numeric_value >= 0.0 else ceili(numeric_value)
		TYPE_BOOL:
			return 1 if value else 0
		TYPE_STRING, TYPE_STRING_NAME:
			var text_value: String = str(value).strip_edges()
			if text_value.is_empty():
				return default_value
			return text_value.to_int()
		_:
			var fallback_text: String = str(value).strip_edges()
			if fallback_text.is_empty():
				return default_value
			return fallback_text.to_int()

func _build_overlay() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_root)

	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.anchor_left = 0.5
	_status_label.anchor_right = 0.5
	_status_label.offset_left = -200
	_status_label.offset_right = 200
	_status_label.offset_top = 10
	_status_label.offset_bottom = 40
	_menu_root.add_child(_status_label)

	_inventory_panel = _create_panel("背包与装备")
	_inventory_panel.custom_minimum_size = Vector2(1040, 620)
	_inventory_panel.offset_left = -520
	_inventory_panel.offset_top = -310
	_inventory_panel.offset_right = 520
	_inventory_panel.offset_bottom = 310
	_character_panel = _create_panel("角色面板")
	_journal_panel = _create_panel("任务面板")
	_skills_panel = _create_panel("技能面板")
	_crafting_panel = _create_panel("制造面板")
	_settings_panel = _create_panel("设置")

	_build_inventory_content(_inventory_panel)
	_build_character_content(_character_panel)
	_build_journal_content(_journal_panel)
	_build_skills_content(_skills_panel)
	_build_crafting_content(_crafting_panel)
	_build_settings_content(_settings_panel)

	_skill_hotbar = SkillHotbarScript.new()
	_skill_hotbar.status_requested.connect(_status)
	_menu_root.add_child(_skill_hotbar)

func _create_panel(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 440)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -350
	panel.offset_top = -220
	panel.offset_right = 350
	panel.offset_bottom = 220

	var root := VBoxContainer.new()
	root.name = "PanelRoot"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 22)
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(_hide_all_menus)
	header.add_child(close_button)

	var separator := HSeparator.new()
	root.add_child(separator)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	_panel_contents[panel] = content

	_menu_root.add_child(panel)
	return panel

func _build_inventory_content(panel: PanelContainer) -> void:
	var content: VBoxContainer = _get_panel_content(panel)
	if not content:
		return
	var main_row := HBoxContainer.new()
	main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 16)
	content.add_child(main_row)

	var left_column := VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 10)
	main_row.add_child(left_column)

	var equipment_title := Label.new()
	equipment_title.text = "装备槽"
	equipment_title.add_theme_font_size_override("font_size", 18)
	left_column.add_child(equipment_title)

	_inventory_equipment_grid = GridContainer.new()
	_inventory_equipment_grid.columns = 5
	_inventory_equipment_grid.add_theme_constant_override("h_separation", 8)
	_inventory_equipment_grid.add_theme_constant_override("v_separation", 8)
	left_column.add_child(_inventory_equipment_grid)

	var slot_order: Array[String] = [
		"head", "body", "hands", "legs", "feet",
		"back", "main_hand", "off_hand", "accessory_1", "accessory_2"
	]
	for slot in slot_order:
		var slot_button := InventoryEquipmentSlotButton.new()
		slot_button.configure(slot)
		slot_button.custom_minimum_size = Vector2(96, 72)
		slot_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot_button.pressed.connect(_on_equipment_slot_pressed.bind(slot))
		slot_button.item_drop_requested.connect(_on_inventory_item_dropped_to_equipment)
		slot_button.equipped_item_drop_requested.connect(_on_equipped_item_dropped_to_equipment)
		_inventory_equipment_grid.add_child(slot_button)
		_inventory_equipment_buttons[slot] = slot_button

	_inventory_summary_label = Label.new()
	_inventory_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_column.add_child(_inventory_summary_label)

	var inventory_title := Label.new()
	inventory_title.text = "拼图背包"
	inventory_title.add_theme_font_size_override("font_size", 18)
	left_column.add_child(inventory_title)

	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.custom_minimum_size = Vector2(0, 330)
	left_column.add_child(inventory_scroll)

	_inventory_grid_view = InventoryGridView.new()
	_inventory_grid_view.item_hovered.connect(_on_inventory_item_hovered)
	_inventory_grid_view.item_unhovered.connect(_on_inventory_item_unhovered)
	_inventory_grid_view.item_selected.connect(_on_inventory_item_selected)
	_inventory_grid_view.grid_interaction.connect(_on_inventory_grid_interaction)
	inventory_scroll.add_child(_inventory_grid_view)

	var right_column := VBoxContainer.new()
	right_column.custom_minimum_size = Vector2(260, 0)
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 10)
	main_row.add_child(right_column)

	var detail_title := Label.new()
	detail_title.text = "物品详情"
	detail_title.add_theme_font_size_override("font_size", 18)
	right_column.add_child(detail_title)

	_inventory_detail_title = Label.new()
	_inventory_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_detail_title.add_theme_font_size_override("font_size", 20)
	right_column.add_child(_inventory_detail_title)

	_inventory_detail_meta = Label.new()
	_inventory_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_column.add_child(_inventory_detail_meta)

	_inventory_detail_description = Label.new()
	_inventory_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(_inventory_detail_description)

	_inventory_action_button = Button.new()
	_inventory_action_button.text = "选择物品"
	_inventory_action_button.disabled = true
	_inventory_action_button.pressed.connect(_on_inventory_action_pressed)
	right_column.add_child(_inventory_action_button)

	_inventory_organize_button = Button.new()
	_inventory_organize_button.text = "整理背包"
	_inventory_organize_button.pressed.connect(_on_inventory_organize_pressed)
	right_column.add_child(_inventory_organize_button)

func _build_character_content(panel: PanelContainer) -> void:
	var content: VBoxContainer = _get_panel_content(panel)
	if not content:
		return
	_character_points_label = Label.new()
	content.add_child(_character_points_label)

	var row_strength := _create_attribute_row("力量", "_on_add_strength")
	_character_strength_label = row_strength.get_node("Value")
	content.add_child(row_strength)

	var row_agility := _create_attribute_row("敏捷", "_on_add_agility")
	_character_agility_label = row_agility.get_node("Value")
	content.add_child(row_agility)

	var row_constitution := _create_attribute_row("体质", "_on_add_constitution")
	_character_constitution_label = row_constitution.get_node("Value")
	content.add_child(row_constitution)

func _create_attribute_row(label_text: String, callback_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)

	var plus_button := Button.new()
	plus_button.text = "+1"
	plus_button.pressed.connect(Callable(self, callback_name))
	row.add_child(plus_button)
	return row

func _build_journal_content(panel: PanelContainer) -> void:
	var content: VBoxContainer = _get_panel_content(panel)
	if not content:
		return
	_journal_list = VBoxContainer.new()
	_journal_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_journal_list)

func _build_skills_content(panel: PanelContainer) -> void:
	var content: VBoxContainer = _get_panel_content(panel)
	if not content:
		return
	var hint := Label.new()
	hint.text = "拖拽技能到下方快捷栏，或右键技能添加到当前快捷栏。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	_skills_list = GridContainer.new()
	_skills_list.columns = 4
	_skills_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skills_list.add_theme_constant_override("h_separation", 10)
	_skills_list.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_skills_list)

func _build_crafting_content(panel: PanelContainer) -> void:
	var content: VBoxContainer = _get_panel_content(panel)
	if not content:
		return
	_crafting_list = VBoxContainer.new()
	_crafting_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_crafting_list)

func _build_settings_content(panel: PanelContainer) -> void:
	var content: VBoxContainer = _get_panel_content(panel)
	if not content:
		return
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(tabs)

	var controls_tab := VBoxContainer.new()
	controls_tab.name = "Controls"
	tabs.add_child(controls_tab)
	tabs.set_tab_title(0, "控制")
	_build_controls_tab(controls_tab)

	var audio_tab := VBoxContainer.new()
	audio_tab.name = "Audio"
	tabs.add_child(audio_tab)
	tabs.set_tab_title(1, "音频")
	_build_audio_tab(audio_tab)

	var display_tab := VBoxContainer.new()
	display_tab.name = "Display"
	tabs.add_child(display_tab)
	tabs.set_tab_title(2, "显示")
	_build_display_tab(display_tab)

func _build_controls_tab(tab: VBoxContainer) -> void:
	_controls_rows.clear()
	for action_variant in InputActions.MENU_ACTIONS:
		var action_name: StringName = action_variant
		var row := HBoxContainer.new()
		tab.add_child(row)

		var action_label := Label.new()
		action_label.text = InputActions.get_action_label(action_name)
		action_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(action_label)

		var binding_label := Label.new()
		binding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(binding_label)

		var rebind_btn := Button.new()
		rebind_btn.text = "重绑"
		rebind_btn.disabled = action_name == InputActions.ACTION_MENU_SETTINGS
		rebind_btn.pressed.connect(_begin_rebind.bind(action_name))
		row.add_child(rebind_btn)

		_controls_rows[action_name] = {
			"label": binding_label,
			"button": rebind_btn
		}

	var hint := Label.new()
	hint.text = "设置面板固定为 ESC，不允许修改。"
	tab.add_child(hint)

	var status := Label.new()
	status.name = "RebindStatus"
	tab.add_child(status)
	_rebind_status_label = status

	var reset_btn := Button.new()
	reset_btn.text = "恢复默认按键"
	reset_btn.pressed.connect(_on_reset_bindings_pressed.bind(status))
	tab.add_child(reset_btn)

func _build_audio_tab(tab: VBoxContainer) -> void:
	_create_audio_slider(tab, "主音量", "master")
	_create_audio_slider(tab, "音乐", "music")
	_create_audio_slider(tab, "音效", "sfx")

func _create_audio_slider(tab: VBoxContainer, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	tab.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = float(ControlSettingsService.get_audio_settings().get(key, 1.0))
	slider.value_changed.connect(_on_audio_slider_changed.bind(key))
	row.add_child(slider)

func _build_display_tab(tab: VBoxContainer) -> void:
	var mode_row := HBoxContainer.new()
	tab.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "窗口模式"
	mode_label.custom_minimum_size = Vector2(90, 0)
	mode_row.add_child(mode_label)
	var mode_option := OptionButton.new()
	mode_option.add_item("窗口", 0)
	mode_option.add_item("全屏", 1)
	mode_option.add_item("无边框全屏", 2)
	mode_option.item_selected.connect(_on_window_mode_selected)
	mode_row.add_child(mode_option)

	var mode_value: String = str(ControlSettingsService.get_display_settings().get("window_mode", "windowed"))
	match mode_value:
		"fullscreen":
			mode_option.select(1)
		"borderless":
			mode_option.select(2)
		_:
			mode_option.select(0)

	var vsync_row := HBoxContainer.new()
	tab.add_child(vsync_row)
	var vsync_label := Label.new()
	vsync_label.text = "垂直同步"
	vsync_label.custom_minimum_size = Vector2(90, 0)
	vsync_row.add_child(vsync_label)
	var vsync_option := OptionButton.new()
	vsync_option.add_item("开启", 1)
	vsync_option.add_item("关闭", 0)
	vsync_option.item_selected.connect(_on_vsync_selected.bind(vsync_option))
	vsync_row.add_child(vsync_option)
	var vsync_on: bool = bool(ControlSettingsService.get_display_settings().get("vsync", true))
	vsync_option.select(0 if vsync_on else 1)

	var scale_row := HBoxContainer.new()
	tab.add_child(scale_row)
	var scale_label := Label.new()
	scale_label.text = "UI 缩放"
	scale_label.custom_minimum_size = Vector2(90, 0)
	scale_row.add_child(scale_label)
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.75
	scale_slider.max_value = 1.5
	scale_slider.step = 0.05
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.value = float(ControlSettingsService.get_display_settings().get("ui_scale", 1.0))
	scale_slider.value_changed.connect(_on_ui_scale_changed)
	scale_row.add_child(scale_slider)

func _load_world_map() -> void:
	var map_scene: PackedScene = load("res://scenes/ui/world_map.tscn")
	if map_scene == null:
		return
	_world_map = map_scene.instantiate()
	add_child(_world_map)
	_world_map.hide()
	if _world_map.has_signal("map_closed"):
		_world_map.connect("map_closed", Callable(self, "_on_world_map_closed"))

func _refresh_inventory() -> void:
	if not GameState:
		return
	_validate_inventory_selection()

	var equip_system = GameState.get_equipment_system() if GameState else null
	for slot in _inventory_equipment_buttons.keys():
		var button: InventoryEquipmentSlotButton = _inventory_equipment_buttons[slot]
		if button == null:
			continue
		var item_data: Dictionary = equip_system.get_equipped_data(slot) if equip_system and equip_system.has_method("get_equipped_data") else {}
		var slot_name: String = equip_system.SLOT_NAMES.get(slot, slot) if equip_system else str(slot)
		var item_name: String = str(item_data.get("name", "空"))
		button.set_equipped_item(str(item_data.get("id", "")), str(item_data.get("instance_id", "")))
		button.text = "%s\n%s" % [slot_name, item_name]
		button.tooltip_text = str(item_data.get("description", "点击查看槽位详情")) if not item_data.is_empty() else "空槽位"

	var dimensions: Vector2i = InventoryModule.get_inventory_dimensions() if InventoryModule and InventoryModule.has_method("get_inventory_dimensions") else Vector2i(5, 4)
	var active_cells: int = InventoryModule.get_active_cell_count() if InventoryModule and InventoryModule.has_method("get_active_cell_count") else _to_int(GameState.inventory_max_slots)
	var visible_items: Array[Dictionary] = InventoryModule.get_visible_items() if InventoryModule and InventoryModule.has_method("get_visible_items") else GameState.inventory_items
	var carry_text: String = ""
	if CarrySystem:
		carry_text = "  负重 %.1f / %.1f kg" % [CarrySystem.get_current_weight(), CarrySystem.get_max_carry_weight()]
	var backpack_name: String = "无背包"
	if equip_system:
		var backpack_id: String = str(equip_system.get_equipped("back"))
		if not backpack_id.is_empty():
			backpack_name = ItemDatabase.get_item_name(backpack_id)
	_inventory_summary_label.text = "%s  格子 %dx%d  已启用 %d 格%s" % [
		backpack_name,
		dimensions.x,
		dimensions.y,
		active_cells,
		carry_text
	]

	if _inventory_grid_view:
		_inventory_grid_view.configure(dimensions.x, dimensions.y, active_cells, visible_items)
		_inventory_grid_view.set_selected_instance(_selected_inventory_instance_id)

	_refresh_inventory_detail()

func _refresh_inventory_detail() -> void:
	if _inventory_detail_title == null:
		return

	var focus: Dictionary = _get_inventory_focus_data()
	if focus.is_empty():
		_inventory_detail_title.text = "将鼠标移到物品上查看详情"
		_inventory_detail_meta.text = ""
		_inventory_detail_description.text = "左键选择物品，拖拽到其他空格可重新摆放，也可以直接拖到装备槽穿戴。已装备物品也能拖回背包或拖到其他装备槽调整。"
		_inventory_action_button.text = "选择物品"
		_inventory_action_button.disabled = true
		return

	var item_id: String = str(focus.get("item_id", ""))
	var item_data: Dictionary = focus.get("item_data", {})
	var entry: Dictionary = focus.get("entry", {})
	var size_data: Vector2i = ItemDatabase.get_inventory_footprint(item_id) if ItemDatabase else Vector2i.ONE
	var count: int = _to_int(entry.get("count", 1), 1)
	var total_weight: float = ItemDatabase.get_item_weight(item_id) * count if ItemDatabase else 0.0
	_inventory_detail_title.text = str(item_data.get("name", item_id))
	_inventory_detail_meta.text = "数量 x%d  尺寸 %dx%d  重量 %.1f kg" % [count, size_data.x, size_data.y, total_weight]
	var description := str(item_data.get("description", ""))
	var bonuses: Dictionary = item_data.get("attributes_bonus", {})
	if not bonuses.is_empty():
		var bonus_parts: Array[String] = []
		for key in bonuses.keys():
			bonus_parts.append("%s %+s" % [str(key), str(bonuses[key])])
		description += "\n\n属性: %s" % ", ".join(PackedStringArray(bonus_parts))
	_inventory_detail_description.text = description

	var action_state: Dictionary = _get_inventory_action_state(focus)
	_inventory_action_button.text = str(action_state.get("label", "无可用操作"))
	_inventory_action_button.disabled = not bool(action_state.get("enabled", false))

func _get_inventory_focus_data() -> Dictionary:
	var instance_id: String = _hovered_inventory_instance_id if not _hovered_inventory_instance_id.is_empty() else _selected_inventory_instance_id
	if not instance_id.is_empty() and GameState and GameState.has_method("get_inventory_item"):
		var entry: Dictionary = GameState.get_inventory_item(instance_id)
		if not entry.is_empty():
			var item_id: String = str(entry.get("id", ""))
			return {
				"kind": "inventory",
				"entry": entry,
				"item_id": item_id,
				"item_data": ItemDatabase.get_item(item_id) if ItemDatabase else {}
			}

	if not _selected_equipment_slot.is_empty():
		var equip_system = GameState.get_equipment_system() if GameState else null
		if equip_system and equip_system.has_method("get_equipped_data"):
			var item_data: Dictionary = equip_system.get_equipped_data(_selected_equipment_slot)
			if not item_data.is_empty():
				return {
					"kind": "equipment",
					"slot": _selected_equipment_slot,
					"entry": item_data,
					"item_id": str(item_data.get("id", "")),
					"item_data": item_data
				}
	return {}

func _get_inventory_action_state(focus: Dictionary) -> Dictionary:
	if focus.is_empty():
		return {"label": "选择物品", "enabled": false}
	var item_id: String = str(focus.get("item_id", ""))
	var item_data: Dictionary = focus.get("item_data", {})
	var kind: String = str(focus.get("kind", ""))
	if kind == "equipment":
		return {
			"label": "卸下",
			"enabled": true
		}
	if bool(item_data.get("usable", false)):
		return {
			"label": "使用",
			"enabled": true
		}
	if bool(item_data.get("equippable", false)):
		return {
			"label": "装备",
			"enabled": not _resolve_target_slot(item_id).is_empty()
		}
	return {"label": "无可用操作", "enabled": false}

func _validate_inventory_selection() -> void:
	if not _selected_inventory_instance_id.is_empty():
		var selected_entry: Dictionary = GameState.get_inventory_item(_selected_inventory_instance_id) if GameState and GameState.has_method("get_inventory_item") else {}
		if selected_entry.is_empty() or not str(selected_entry.get("equipped_slot", "")).is_empty():
			_selected_inventory_instance_id = ""
	if not _hovered_inventory_instance_id.is_empty():
		var hovered_entry: Dictionary = GameState.get_inventory_item(_hovered_inventory_instance_id) if GameState and GameState.has_method("get_inventory_item") else {}
		if hovered_entry.is_empty() or not str(hovered_entry.get("equipped_slot", "")).is_empty():
			_hovered_inventory_instance_id = ""
	if not _selected_equipment_slot.is_empty():
		var equip_system = GameState.get_equipment_system() if GameState else null
		if equip_system == null or str(equip_system.get_equipped(_selected_equipment_slot)).is_empty():
			_selected_equipment_slot = ""

func _on_inventory_item_hovered(instance_id: String) -> void:
	_hovered_inventory_instance_id = instance_id
	_refresh_inventory_detail()

func _on_inventory_item_unhovered(instance_id: String) -> void:
	if _hovered_inventory_instance_id == instance_id:
		_hovered_inventory_instance_id = ""
	_refresh_inventory_detail()

func _on_inventory_item_selected(instance_id: String) -> void:
	_selected_inventory_instance_id = instance_id
	_selected_equipment_slot = ""
	_refresh_inventory_detail()

func _on_equipment_slot_pressed(slot: String) -> void:
	_selected_equipment_slot = slot
	_selected_inventory_instance_id = ""
	_refresh_inventory_detail()

func _on_inventory_action_pressed() -> void:
	var focus: Dictionary = _get_inventory_focus_data()
	if focus.is_empty():
		return
	var equip_system = GameState.get_equipment_system() if GameState else null
	var item_id: String = str(focus.get("item_id", ""))
	match str(focus.get("kind", "")):
		"equipment":
			if equip_system and equip_system.has_method("unequip"):
				if equip_system.unequip(str(focus.get("slot", ""))):
					_status("已卸下 %s" % ItemDatabase.get_item_name(item_id))
				else:
					_status("当前没有足够空间卸下该装备")
		"inventory":
			var item_data: Dictionary = focus.get("item_data", {})
			var entry: Dictionary = focus.get("entry", {})
			if bool(item_data.get("usable", false)):
				if InventoryModule and InventoryModule.use_item(item_id):
					_status("已使用 %s" % ItemDatabase.get_item_name(item_id))
				else:
					_status("无法使用该物品")
			elif bool(item_data.get("equippable", false)) and equip_system and equip_system.has_method("equip"):
				var target_slot: String = _resolve_target_slot(item_id)
				if target_slot.is_empty():
					_status("当前没有可用装备槽")
				elif equip_system.has_method("equip_instance") and equip_system.equip_instance(str(entry.get("instance_id", "")), target_slot):
					_status("已装备 %s" % ItemDatabase.get_item_name(item_id))
				elif equip_system.equip(item_id, target_slot):
					_status("已装备 %s" % ItemDatabase.get_item_name(item_id))
				else:
					_status("装备失败，可能空间不足或槽位不匹配")
	_refresh_inventory()

func _on_inventory_item_dropped_to_equipment(slot: String, instance_id: String) -> void:
	var equip_system = GameState.get_equipment_system() if GameState else null
	if equip_system == null or not equip_system.has_method("equip_instance"):
		_status("装备系统不可用")
		return

	var entry: Dictionary = GameState.get_inventory_item(instance_id) if GameState and GameState.has_method("get_inventory_item") else {}
	var item_id: String = str(entry.get("id", ""))
	if item_id.is_empty():
		_status("找不到要装备的物品")
		return

	if equip_system.equip_instance(instance_id, slot):
		_hovered_inventory_instance_id = ""
		_selected_inventory_instance_id = ""
		_selected_equipment_slot = slot
		_status("已装备 %s" % ItemDatabase.get_item_name(item_id))
	else:
		_status("无法装备到该槽位")
	_refresh_inventory()

func _on_equipped_item_dropped_to_equipment(target_slot: String, source_slot: String) -> void:
	var equip_system = GameState.get_equipment_system() if GameState else null
	if equip_system == null or not equip_system.has_method("move_equipped_item"):
		_status("装备系统不可用")
		return

	if equip_system.move_equipped_item(source_slot, target_slot):
		_selected_equipment_slot = target_slot
		_hovered_inventory_instance_id = ""
		_selected_inventory_instance_id = ""
		_status("已调整装备槽位")
	else:
		_status("无法移动到该装备槽")
	_refresh_inventory()

func _on_inventory_organize_pressed() -> void:
	if GameState and GameState.has_method("refresh_inventory_capacity"):
		if GameState.refresh_inventory_capacity(false):
			_status("背包已整理")
		else:
			_status("背包空间不足，无法整理")
	_refresh_inventory()

func _on_inventory_grid_interaction(message: String) -> void:
	_status(message)
	_refresh_inventory()

func _on_inventory_event(_payload: Dictionary) -> void:
	if _inventory_panel and _inventory_panel.visible:
		_refresh_inventory()

func _on_equipment_system_ready(_system: Node) -> void:
	_bind_inventory_equipment_system()
	if _inventory_panel and _inventory_panel.visible:
		_refresh_inventory()

func _bind_inventory_equipment_system() -> void:
	var equip_system = GameState.get_equipment_system() if GameState else null
	if equip_system == null or equip_system == _inventory_equipment_system:
		return
	_inventory_equipment_system = equip_system
	if equip_system.has_signal("item_equipped"):
		equip_system.item_equipped.connect(_on_inventory_equipment_slot_changed)
	if equip_system.has_signal("item_unequipped"):
		equip_system.item_unequipped.connect(_on_inventory_equipment_slot_changed)
	if equip_system.has_signal("item_broken"):
		equip_system.item_broken.connect(_on_inventory_equipment_slot_changed)
	if equip_system.has_signal("durability_changed"):
		equip_system.durability_changed.connect(_on_inventory_equipment_durability_changed)
	if equip_system.has_signal("ammo_changed"):
		equip_system.ammo_changed.connect(_on_inventory_equipment_ammo_changed)

func _on_inventory_equipment_slot_changed(_slot: String, _item_id: String) -> void:
	if _inventory_panel and _inventory_panel.visible:
		_refresh_inventory()

func _on_inventory_equipment_durability_changed(_slot: String, _durability_percent: float) -> void:
	if _inventory_panel and _inventory_panel.visible:
		_refresh_inventory()

func _on_inventory_equipment_ammo_changed(_ammo_type: String, _current: int, _max_ammo: int) -> void:
	if _inventory_panel and _inventory_panel.visible:
		_refresh_inventory()

func _resolve_target_slot(item_id: String) -> String:
	var equip_system = GameState.get_equipment_system() if GameState else null
	if equip_system == null:
		return ""
	var slot: String = ItemDatabase.get_equip_slot(item_id) if ItemDatabase else ""
	if slot == "accessory":
		if str(equip_system.get_equipped("accessory_1")).is_empty():
			return "accessory_1"
		if str(equip_system.get_equipped("accessory_2")).is_empty():
			return "accessory_2"
		return "accessory_1"
	return slot

func _refresh_character() -> void:
	var attr_system: Node = get_node_or_null("/root/AttributeSystem")
	var xp_system: Node = get_node_or_null("/root/ExperienceSystem")
	if not attr_system:
		_character_points_label.text = "属性系统不可用"
		return

	var points: int = 0
	if attr_system.has_method("get_available_points"):
		points = _to_int(attr_system.get_available_points(), 0)
	if xp_system and xp_system.has_method("get_available_points"):
		var available_points: Variant = xp_system.get_available_points()
		if available_points is Dictionary:
			points = _to_int((available_points as Dictionary).get("stat_points", points), points)

	_character_points_label.text = "可用属性点: %d" % points
	var snapshot: Dictionary = {}
	if GameState and GameState.has_method("get_player_attributes_snapshot"):
		snapshot = GameState.get_player_attributes_snapshot()
	elif attr_system.has_method("get_actor_attributes_snapshot"):
		snapshot = attr_system.get_actor_attributes_snapshot("player")

	_character_strength_label.text = str(_to_int(snapshot.get("strength", 0)))
	_character_agility_label.text = str(_to_int(snapshot.get("agility", 0)))
	_character_constitution_label.text = str(_to_int(snapshot.get("constitution", 0)))

func _refresh_journal() -> void:
	_clear_children(_journal_list)
	if not QuestSystem or not QuestSystem.has_method("get_active_quests"):
		var empty_label := Label.new()
		empty_label.text = "任务系统不可用"
		_journal_list.add_child(empty_label)
		return

	var active_quests: Array = QuestSystem.get_active_quests()
	if active_quests.is_empty():
		var empty := Label.new()
		empty.text = "当前没有进行中的任务"
		_journal_list.add_child(empty)
		return

	for quest_variant in active_quests:
		var quest: Dictionary = quest_variant
		var line := Label.new()
		line.text = "• %s" % str(quest.get("title", "未知任务"))
		_journal_list.add_child(line)

func _refresh_skills() -> void:
	_clear_children(_skills_list)
	if not SkillSystem or not SkillSystem.has_method("get_all_skills"):
		var empty_label := Label.new()
		empty_label.text = "技能系统不可用"
		_skills_list.add_child(empty_label)
		return
	var skills: Dictionary = SkillSystem.get_all_skills()
	if skills.is_empty():
		var empty := Label.new()
		empty.text = "暂无技能数据"
		_skills_list.add_child(empty)
		return

	var skill_ids: Array[String] = []
	for skill_id_variant in skills.keys():
		skill_ids.append(str(skill_id_variant))
	skill_ids.sort_custom(func(a: String, b: String) -> bool:
		var skill_a: Dictionary = skills.get(a, {})
		var skill_b: Dictionary = skills.get(b, {})
		var tree_a: String = str(skill_a.get("tree_id", ""))
		var tree_b: String = str(skill_b.get("tree_id", ""))
		if tree_a == tree_b:
			return str(skill_a.get("name", a)) < str(skill_b.get("name", b))
		return tree_a < tree_b
	)

	for skill_id in skill_ids:
		var skill: Dictionary = skills[skill_id]
		var item: Control = SkillPanelItemScript.new()
		item.configure(skill_id, skill)
		item.add_to_hotbar_requested.connect(_on_skill_add_to_hotbar_requested)
		_skills_list.add_child(item)

func _refresh_crafting() -> void:
	_clear_children(_crafting_list)
	if not CraftingSystem or not CraftingSystem.has_method("get_available_recipes"):
		var empty_label := Label.new()
		empty_label.text = "制造系统不可用"
		_crafting_list.add_child(empty_label)
		return

	var recipes: Array = CraftingSystem.get_available_recipes("")
	if recipes.is_empty():
		var empty := Label.new()
		empty.text = "暂无可制造配方"
		_crafting_list.add_child(empty)
		return

	for recipe_variant in recipes:
		var recipe: Dictionary = recipe_variant
		var line := Label.new()
		line.text = "• %s" % str(recipe.get("name", recipe.get("id", "未知配方")))
		_crafting_list.add_child(line)

func _refresh_controls_tab() -> void:
	for action_variant in _controls_rows.keys():
		var action_name: StringName = action_variant
		var row_data: Dictionary = _controls_rows[action_name]
		var label: Label = row_data.get("label")
		var binding: Dictionary = ControlSettingsService.get_binding(action_name)
		label.text = InputActions.keycode_to_text(_to_int(binding.get("keycode", KEY_NONE), KEY_NONE))

func _begin_rebind(action_name: StringName) -> void:
	_pending_rebind_action = action_name
	if _rebind_status_label:
		_rebind_status_label.text = "请按下新的按键：%s" % InputActions.get_action_label(action_name)
		_pending_rebind_label = _rebind_status_label
	_status("等待按键输入...")

func _on_reset_bindings_pressed(status: Label) -> void:
	ControlSettingsService.reset_defaults()
	_refresh_controls_tab()
	status.text = "已恢复默认按键"
	_status("按键已恢复默认")

func _on_audio_slider_changed(value: float, key: String) -> void:
	ControlSettingsService.set_audio_setting(key, value)

func _on_window_mode_selected(index: int) -> void:
	var mode_name: String = "windowed"
	match index:
		1:
			mode_name = "fullscreen"
		2:
			mode_name = "borderless"
	ControlSettingsService.set_display_setting("window_mode", mode_name)

func _on_vsync_selected(_index: int, option: OptionButton) -> void:
	ControlSettingsService.set_display_setting("vsync", option.get_selected_id() == 1)

func _on_ui_scale_changed(value: float) -> void:
	ControlSettingsService.set_display_setting("ui_scale", value)

func _on_skill_add_to_hotbar_requested(skill_id: String) -> void:
	if _skill_hotbar == null:
		_status("快捷栏不可用")
		return
	_skill_hotbar.add_skill_to_active_group(skill_id)
	_refresh_skills()

func _on_add_strength() -> void:
	_allocate_attribute("strength")

func _on_add_agility() -> void:
	_allocate_attribute("agility")

func _on_add_constitution() -> void:
	_allocate_attribute("constitution")

func _allocate_attribute(attribute_name: String) -> void:
	var attr_system: Node = get_node_or_null("/root/AttributeSystem")
	if not attr_system:
		return

	var result: Dictionary = attr_system.allocate_player_attributes({attribute_name: 1})
	if bool(result.get("success", false)):
		_status("已提升%s" % attribute_name)
	else:
		_status("属性提升失败: %s" % str(result.get("reason", "unknown")))
	_refresh_character()

func _hide_all_menus() -> void:
	_pending_rebind_action = StringName()
	if _pending_rebind_label:
		_pending_rebind_label.text = ""
		_pending_rebind_label = null
	_hovered_inventory_instance_id = ""
	_selected_inventory_instance_id = ""
	_selected_equipment_slot = ""
	_hide_all_panels()
	if _world_map and _world_map.visible:
		_world_map.call("hide_map")

func _hide_all_panels() -> void:
	_inventory_panel.hide()
	_character_panel.hide()
	_journal_panel.hide()
	_skills_panel.hide()
	_crafting_panel.hide()
	_settings_panel.hide()

func _is_panel_open(action_name: StringName) -> bool:
	match action_name:
		InputActions.ACTION_MENU_INVENTORY:
			return _inventory_panel.visible
		InputActions.ACTION_MENU_CHARACTER:
			return _character_panel.visible
		InputActions.ACTION_MENU_JOURNAL:
			return _journal_panel.visible
		InputActions.ACTION_MENU_SKILLS:
			return _skills_panel.visible
		InputActions.ACTION_MENU_CRAFTING:
			return _crafting_panel.visible
		InputActions.ACTION_MENU_SETTINGS:
			return _settings_panel.visible
		InputActions.ACTION_MENU_MAP:
			return _world_map != null and _world_map.visible
		_:
			return false

func _on_world_map_closed() -> void:
	_status("地图已关闭")

func _status(message: String) -> void:
	if _status_label:
		_status_label.text = message

func _clear_children(node: Node) -> void:
	if not node:
		return
	for child in node.get_children():
		child.queue_free()

func _get_panel_content(panel: PanelContainer) -> VBoxContainer:
	if _panel_contents.has(panel):
		return _panel_contents[panel]
	var root := panel.get_child(0) if panel and panel.get_child_count() > 0 else null
	if root == null:
		return null
	for child in root.get_children():
		if child is VBoxContainer and child.name == "Content":
			return child
	return null
