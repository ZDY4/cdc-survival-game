extends InteractionOption
class_name PickupInteractionOption

@export var item_id: String = ""
@export var min_count: int = 1
@export var max_count: int = 1
@export var remove_target_after_pickup: bool = true

func _init() -> void:
	option_id = "pickup"
	display_name = "拾取"
	priority = 900

func is_available(_interactable: Node) -> bool:
	return enabled and not item_id.is_empty()

func execute(interactable: Node) -> void:
	if item_id.is_empty():
		return
	
	var count := randi_range(min_count, max_count)
	InventoryModule.add_item(item_id, count)
	
	var item_name := item_id
	if ItemDatabase and ItemDatabase.has_method("get_item_name"):
		item_name = str(ItemDatabase.get_item_name(item_id))
	
	if DialogModule:
		DialogModule.show_dialog("获得 %s x%d" % [item_name, count])
	
	if EventBus:
		EventBus.emit(EventBus.EventType.ITEM_ACQUIRED, {
			"items": [{"id": item_id, "count": count}],
			"source": interactable.name
		})
	
	if remove_target_after_pickup and interactable:
		interactable.call_deferred("queue_free")
