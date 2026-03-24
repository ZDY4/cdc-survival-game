extends "res://modules/interaction/options/interaction_option.gd"
class_name PickupInteractionOption
## LEGACY AUTHORITY BOUNDARY:
## Pickup option execution remains a transitional Godot path. Keep this file as
## client-facing glue; authoritative inventory/item transfer validation should
## move to Rust runtime/protocol instead of expanding local execute() logic.

const ItemIdResolver = preload("res://core/item_id_resolver.gd")

@export var item_id: String = ""
@export var min_count: int = 1
@export var max_count: int = 1
@export var pickup_root_path: NodePath = NodePath("..")

func _init() -> void:
	option_id = "pickup"
	display_name = "拾取"
	priority = 900

func is_available(_interactable: Node) -> bool:
	if not enabled or item_id.is_empty():
		return false
	if ItemDatabase and ItemDatabase.has_method("has_item"):
		return bool(ItemDatabase.has_item(item_id))
	return not ItemIdResolver.load_item_data_from_json(item_id).is_empty()

func execute(interactable: Node) -> void:
	var resolved_item_id: String = item_id
	if ItemDatabase and ItemDatabase.has_method("resolve_item_id"):
		resolved_item_id = str(ItemDatabase.resolve_item_id(item_id))
	else:
		resolved_item_id = ItemIdResolver.resolve_item_id(item_id)

	if resolved_item_id.is_empty():
		return

	var min_amount: int = max(1, min(min_count, max_count))
	var max_amount: int = max(min_amount, max(min_count, max_count))
	var count: int = randi_range(min_amount, max_amount)
	var added: bool = InventoryModule.add_item(resolved_item_id, count)
	if not added:
		return

	var item_name: String = resolved_item_id
	if ItemDatabase and ItemDatabase.has_method("get_item_name"):
		item_name = str(ItemDatabase.get_item_name(resolved_item_id))

	if DialogModule:
		DialogModule.show_dialog("获得 %s x%d" % [item_name, count])

	var pickup_root: Node = null
	if interactable != null:
		pickup_root = interactable.get_node_or_null(pickup_root_path)
		if pickup_root == null:
			pickup_root = interactable.get_parent()

	var source_name: String = ""
	if interactable != null:
		source_name = interactable.name
	if pickup_root != null:
		source_name = pickup_root.name

	if EventBus:
		EventBus.emit(EventBus.EventType.ITEM_ACQUIRED, {
			"items": [{"id": resolved_item_id, "count": count}],
			"source": source_name
		})

	if pickup_root != null:
		pickup_root.call_deferred("queue_free")
