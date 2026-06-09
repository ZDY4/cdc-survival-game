extends RefCounted

var active_trade_feedback: Dictionary = {}
var active_container_feedback: Dictionary = {}
var active_character_feedback: Dictionary = {}
var active_inventory_feedback: Dictionary = {}


func record_container_feedback(result: Dictionary, action: String, container_id: String, item_id: String, count: int) -> void:
	if bool(result.get("success", false)) and not bool(result.get("partial_success", false)):
		active_container_feedback = {}
		return
	active_container_feedback = result.duplicate(true)
	active_container_feedback["type"] = "error"
	active_container_feedback["action"] = action
	active_container_feedback["container_id"] = str(result.get("container_id", container_id))
	active_container_feedback["item_id"] = str(result.get("item_id", item_id))
	active_container_feedback["count"] = count


func record_trade_feedback(result: Dictionary, action: String, shop_id: String, item_id: String, count: int) -> void:
	if bool(result.get("success", false)):
		active_trade_feedback = {}
		return
	active_trade_feedback = result.duplicate(true)
	active_trade_feedback["type"] = "error"
	active_trade_feedback["action"] = action
	active_trade_feedback["shop_id"] = str(result.get("shop_id", shop_id))
	active_trade_feedback["item_id"] = str(result.get("item_id", item_id))
	active_trade_feedback["count"] = count


func record_inventory_feedback(result: Dictionary, action: String, item_id: String, count: int) -> void:
	active_inventory_feedback = result.duplicate(true)
	active_inventory_feedback["type"] = "success" if bool(result.get("success", false)) else "error"
	active_inventory_feedback["action"] = action
	active_inventory_feedback["item_id"] = str(result.get("item_id", item_id))
	active_inventory_feedback["count"] = int(result.get("count", count))


func record_character_feedback(result: Dictionary, action: String, slot_id: String, item_id: String) -> void:
	if bool(result.get("success", false)):
		active_character_feedback = {}
		return
	active_character_feedback = result.duplicate(true)
	active_character_feedback["type"] = "error"
	active_character_feedback["action"] = action
	active_character_feedback["slot_id"] = str(result.get("slot_id", slot_id))
	active_character_feedback["item_id"] = str(result.get("item_id", item_id))
