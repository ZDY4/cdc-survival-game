extends RefCounted

var latest_queue_result: Dictionary = {}
var latest_pending_result: Dictionary = {}


func clear_pending_result() -> void:
	latest_pending_result = {}


func record_queue_result(result: Dictionary, trigger: String, pending_crafting: Dictionary) -> void:
	if result.is_empty():
		latest_queue_result = {}
		return
	latest_queue_result = queue_feedback_snapshot(result, trigger, pending_crafting)


func record_queue_cleared() -> void:
	latest_queue_result = {
		"active": false,
		"reason": "queue_cleared",
		"entry_count": 0,
		"total_count": 0,
	}


func record_pending_cancelled(result: Dictionary, reason: String, remaining_queue: Array) -> void:
	latest_pending_result = pending_cancel_feedback_snapshot(result, reason, remaining_queue)
	latest_queue_result = {
		"active": true,
		"reason": "pending_cancelled",
		"cancel_reason": reason,
		"remaining_queue_count": remaining_queue.size(),
		"remaining_total_count": queue_total_count(remaining_queue),
	}


func queue_snapshot(entries: Array) -> Dictionary:
	return {
		"entries": entries.duplicate(true),
		"entry_count": entries.size(),
		"total_count": queue_total_count(entries),
		"latest_result": latest_queue_result.duplicate(true),
	}


func normalize_queue(entries: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry in _array_or_empty(entries):
		var data: Dictionary = _dictionary_or_empty(entry)
		var recipe_id := str(data.get("recipe_id", "")).strip_edges()
		if recipe_id.is_empty():
			continue
		output.append({
			"recipe_id": recipe_id,
			"count": max(1, int(data.get("count", 1))),
		})
	return output


func queue_total_count(entries: Array) -> int:
	var total := 0
	for entry in entries:
		total += max(1, int(_dictionary_or_empty(entry).get("count", 1)))
	return total


func queue_feedback_snapshot(result: Dictionary, trigger: String, pending_crafting: Dictionary) -> Dictionary:
	var remaining_queue: Array = _array_or_empty(result.get("remaining_queue", []))
	var pending: Dictionary = _dictionary_or_empty(pending_crafting)
	var summary := ""
	if bool(result.get("pending", false)):
		summary = "队列进行中: 已完成 %d 次，正在制作 %s x%d，剩余 %d 项" % [
			int(result.get("completed_count", 0)),
			str(pending.get("recipe_id", "")),
			max(1, int(pending.get("count", 1))) if not pending.is_empty() else 1,
			int(result.get("remaining_queue_count", remaining_queue.size())),
		]
	elif bool(result.get("success", false)):
		summary = "队列完成: 已制作 %d 次" % int(result.get("completed_count", 0))
	elif bool(result.get("partial_success", false)):
		summary = "队列部分完成: 已制作 %d 次，失败 %d 项" % [
			int(result.get("completed_count", 0)),
			int(result.get("failed_count", 0)),
		]
	else:
		summary = "队列失败: %s" % str(result.get("reason", "unknown"))
	return {
		"active": true,
		"trigger": trigger,
		"success": bool(result.get("success", false)),
		"partial_success": bool(result.get("partial_success", false)),
		"pending": bool(result.get("pending", false)),
		"started_pending": bool(result.get("started_pending", false)),
		"completed_count": int(result.get("completed_count", 0)),
		"failed_count": int(result.get("failed_count", 0)),
		"remaining_queue_count": int(result.get("remaining_queue_count", remaining_queue.size())),
		"remaining_total_count": queue_total_count(remaining_queue),
		"queue_empty": bool(result.get("queue_empty", remaining_queue.is_empty())),
		"pending_recipe_id": str(pending.get("recipe_id", "")),
		"pending_count": max(1, int(pending.get("count", 1))) if not pending.is_empty() else 0,
		"summary": summary,
		"reason": str(result.get("reason", "")),
	}


func pending_cancel_feedback_snapshot(result: Dictionary, reason: String, remaining_queue: Array) -> Dictionary:
	var cancelled: Dictionary = _dictionary_or_empty(result.get("pending_crafting", {}))
	if cancelled.is_empty():
		cancelled = _dictionary_or_empty(result.get("cancelled_crafting", {}))
	if cancelled.is_empty():
		return {}
	var required_ap: float = max(0.0, float(cancelled.get("required_ap", 0.0)))
	var progress_ap: float = clampf(float(cancelled.get("progress_ap", 0.0)), 0.0, required_ap)
	var remaining_ap: float = max(0.0, float(cancelled.get("remaining_ap", required_ap - progress_ap)))
	var recipe_id := str(cancelled.get("recipe_id", ""))
	return {
		"active": true,
		"reason": "pending_cancelled",
		"cancel_reason": reason,
		"recipe_id": recipe_id,
		"count": max(1, int(cancelled.get("count", 1))),
		"required_ap": required_ap,
		"progress_ap": progress_ap,
		"remaining_ap": remaining_ap,
		"progress_ratio": 0.0 if required_ap <= 0.0 else progress_ap / required_ap,
		"turn_policy": _dictionary_or_empty(result.get("turn_policy", {})).duplicate(true),
		"remaining_queue_count": remaining_queue.size(),
		"remaining_total_count": queue_total_count(remaining_queue),
		"pending_crafting": cancelled.duplicate(true),
		"summary": "已取消正在制作: %s x%d | 进度 %.1f/%.1f AP | 剩余 %.1f AP" % [
			recipe_id,
			max(1, int(cancelled.get("count", 1))),
			progress_ap,
			required_ap,
			remaining_ap,
		],
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
