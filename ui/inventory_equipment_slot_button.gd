extends Button

signal item_drop_requested(slot_name: String, instance_id: String)
signal equipped_item_drop_requested(target_slot_name: String, source_slot_name: String)

var slot_name: String = ""
var equipped_item_id: String = ""
var equipped_instance_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func configure(next_slot_name: String) -> void:
	slot_name = next_slot_name


func set_equipped_item(item_id: String, instance_id: String) -> void:
	equipped_item_id = item_id
	equipped_instance_id = instance_id


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data as Dictionary

	var payload_type: String = str(payload.get("type", ""))
	var item_id: String = str(payload.get("item_id", ""))
	if item_id.is_empty() or ItemDatabase == null or not ItemDatabase.is_equippable(item_id):
		return false
	if payload_type == "equipped_item" and str(payload.get("slot", "")) == slot_name:
		return false
	if payload_type != "inventory_item" and payload_type != "equipped_item":
		return false

	var item_slot: String = ItemDatabase.get_equip_slot(item_id)
	if item_slot == slot_name:
		return true
	if item_slot == "main_hand" and slot_name in ["main_hand", "off_hand"]:
		return true
	if item_slot == "accessory" and slot_name in ["accessory_1", "accessory_2"]:
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	var payload: Dictionary = data as Dictionary
	match str(payload.get("type", "")):
		"inventory_item":
			var instance_id: String = str(payload.get("instance_id", ""))
			if instance_id.is_empty():
				return
			item_drop_requested.emit(slot_name, instance_id)
		"equipped_item":
			var source_slot: String = str(payload.get("slot", ""))
			if source_slot.is_empty():
				return
			equipped_item_drop_requested.emit(slot_name, source_slot)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if equipped_instance_id.is_empty() or equipped_item_id.is_empty():
		return null
	var preview := duplicate() as Control
	if preview == null:
		return null
	preview.custom_minimum_size = size
	set_drag_preview(preview)
	return {
		"type": "equipped_item",
		"slot": slot_name,
		"instance_id": equipped_instance_id,
		"item_id": equipped_item_id
	}
