extends InteractionOption
class_name ContainerInteractionOption

@export var container_title: String = "容器"
@export var container_items: Array[Dictionary] = []
@export var clear_after_take_all: bool = true
@export var auto_close_after_take_all: bool = true

func _init() -> void:
	option_id = "open_container"
	display_name = "打开"
	priority = 850

func execute(interactable: Node) -> void:
	var popup := AcceptDialog.new()
	popup.title = container_title
	popup.dialog_text = "容器内容"
	popup.unresizable = true
	
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(420, 280)
	popup.add_child(container)
	
	var items_list := ItemList.new()
	items_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(items_list)
	_refresh_items_list(items_list)
	
	var take_all_btn := Button.new()
	take_all_btn.text = "全部拾取"
	take_all_btn.pressed.connect(func():
		_take_all_items(interactable)
		_refresh_items_list(items_list)
		if auto_close_after_take_all:
			popup.hide()
			popup.queue_free()
	)
	container.add_child(take_all_btn)
	
	interactable.get_tree().root.add_child(popup)
	popup.popup_centered(Vector2i(420, 320))
	
	if EventBus:
		EventBus.emit(EventBus.EventType.SCENE_INTERACTION, {
			"type": "open_container",
			"target": interactable.name,
			"items_count": container_items.size()
		})

func _refresh_items_list(items_list: ItemList) -> void:
	items_list.clear()
	if container_items.is_empty():
		items_list.add_item("（空）")
		return
	for entry in container_items:
		var item_id := str(entry.get("id", ""))
		var count := int(entry.get("count", 1))
		var item_name := item_id
		if ItemDatabase and ItemDatabase.has_method("get_item_name"):
			item_name = str(ItemDatabase.get_item_name(item_id))
		items_list.add_item("%s x%d" % [item_name, count])

func _take_all_items(interactable: Node) -> void:
	if container_items.is_empty():
		return
	
	for entry in container_items:
		var item_id := str(entry.get("id", ""))
		var count := int(entry.get("count", 1))
		if not item_id.is_empty():
			InventoryModule.add_item(item_id, count)
	
	if EventBus:
		EventBus.emit(EventBus.EventType.ITEM_ACQUIRED, {
			"items": container_items.duplicate(true),
			"source": interactable.name
		})
	
	if DialogModule:
		DialogModule.show_dialog("已拾取容器中的所有物品。")
	
	if clear_after_take_all:
		container_items.clear()
