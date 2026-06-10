extends RefCounted

const ContainerTransactions = preload("res://scripts/core/economy/container_transactions.gd")

var _container_transactions := ContainerTransactions.new()


func take_item(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}, stack_index: int = 0) -> Dictionary:
	return _container_transactions.take_item_from_container(simulation, actor_id, container_id, item_id, count, item_library, stack_index)


func take_money(simulation: RefCounted, actor_id: int, container_id: String, count: int = -1) -> Dictionary:
	return _container_transactions.take_money_from_container(simulation, actor_id, container_id, count)


func take_all(simulation: RefCounted, actor_id: int, container_id: String, item_library: Dictionary = {}, include_money: bool = true) -> Dictionary:
	return _container_transactions.take_all_from_container(simulation, actor_id, container_id, item_library, include_money)


func store_item(simulation: RefCounted, actor_id: int, container_id: String, item_id: String, count: int, item_library: Dictionary = {}, stack_index: int = 0) -> Dictionary:
	return _container_transactions.store_item_in_container(simulation, actor_id, container_id, item_id, count, item_library, stack_index)


func store_all(simulation: RefCounted, actor_id: int, container_id: String, item_library: Dictionary = {}) -> Dictionary:
	return _container_transactions.store_all_in_container(simulation, actor_id, container_id, item_library)


func close(simulation: RefCounted, actor_id: int, reason: String = "closed") -> Dictionary:
	var actor: RefCounted = simulation.actor_registry.get_actor(actor_id)
	if actor == null:
		return {"success": false, "reason": "actor_missing"}
	var container_id := str(actor.active_container_id)
	if container_id.is_empty():
		return {"success": false, "reason": "container_inactive"}
	actor.active_container_id = ""
	simulation.emit_event("container_closed", {
		"actor_id": actor_id,
		"container_id": container_id,
		"reason": reason,
	})
	return {"success": true, "container_id": container_id}
