extends RefCounted

const AUTO_TICK_INTERVAL_SEC := 0.45
const OBSERVE_SPEEDS: Array[Dictionary] = [
	{"id": "x1", "multiplier": 1.0},
	{"id": "x2", "multiplier": 2.0},
	{"id": "x5", "multiplier": 5.0},
	{"id": "x10", "multiplier": 10.0},
]

var info_panel_pages: Array[Dictionary] = [
	{"id": "overview", "title": "Overview", "tab_label": "Overview"},
	{"id": "selection", "title": "Selection", "tab_label": "Select"},
	{"id": "actor", "title": "Selected Actor", "tab_label": "Actor"},
	{"id": "world", "title": "World", "tab_label": "World"},
	{"id": "interaction", "title": "Interaction", "tab_label": "Interact"},
	{"id": "turn_sys", "title": "Turn System", "tab_label": "Turn"},
	{"id": "events", "title": "Events", "tab_label": "Events"},
	{"id": "ai", "title": "AI", "tab_label": "AI"},
	{"id": "performance", "title": "Performance", "tab_label": "Perf"},
]
var active_info_panel_index: int = 0
var auto_tick_enabled := false
var auto_tick_elapsed_sec := 0.0
var observe_mode_enabled := false
var observe_speed_id := "x1"


func toggle_auto_tick(ui_blocked: bool) -> Dictionary:
	if observe_mode_enabled:
		return toggle_observe_playback(ui_blocked)
	if ui_blocked:
		return {"success": false, "reason": "ui_blocked", "enabled": auto_tick_enabled}
	auto_tick_enabled = not auto_tick_enabled
	auto_tick_elapsed_sec = 0.0
	return {"success": true, "enabled": auto_tick_enabled}


func set_observe_mode(enabled: bool, ui_blocked: bool) -> Dictionary:
	if ui_blocked:
		return {"success": false, "reason": "ui_blocked", "observe_mode": observe_mode_enabled}
	observe_mode_enabled = enabled
	if not observe_mode_enabled:
		auto_tick_enabled = false
		auto_tick_elapsed_sec = 0.0
	return {
		"success": true,
		"observe_mode": observe_mode_enabled,
		"observe_playback": observe_playback_enabled(),
		"observe_speed": observe_speed_id,
	}


func toggle_observe_playback(ui_blocked: bool) -> Dictionary:
	if not observe_mode_enabled:
		return {"success": false, "reason": "observe_mode_disabled", "observe_playback": false}
	if ui_blocked:
		return {"success": false, "reason": "ui_blocked", "observe_playback": observe_playback_enabled()}
	auto_tick_enabled = not auto_tick_enabled
	auto_tick_elapsed_sec = 0.0
	return {
		"success": true,
		"observe_playback": observe_playback_enabled(),
		"auto_tick": auto_tick_enabled,
		"observe_speed": observe_speed_id,
	}


func cycle_observe_speed() -> Dictionary:
	if not observe_mode_enabled:
		return {"success": false, "reason": "observe_mode_disabled", "observe_speed": observe_speed_id}
	var current_index := observe_speed_index(observe_speed_id)
	var next_index := (current_index + 1) % OBSERVE_SPEEDS.size()
	return set_observe_speed(str(OBSERVE_SPEEDS[next_index].get("id", "x1")))


func set_observe_speed(speed_id: String) -> Dictionary:
	if not observe_mode_enabled:
		return {"success": false, "reason": "observe_mode_disabled", "observe_speed": observe_speed_id}
	var normalized := speed_id.strip_edges().to_lower()
	if observe_speed_index(normalized) < 0:
		return {"success": false, "reason": "unknown_observe_speed", "observe_speed": observe_speed_id}
	observe_speed_id = normalized
	auto_tick_elapsed_sec = 0.0
	return {
		"success": true,
		"observe_speed": observe_speed_id,
		"interval_sec": auto_tick_interval_sec(),
	}


func cycle_info_panel(direction: int) -> Dictionary:
	if info_panel_pages.size() <= 1:
		return {"success": false, "reason": "not_enough_info_pages"}
	active_info_panel_index = posmod(active_info_panel_index + direction, info_panel_pages.size())
	var page := current_info_panel_page()
	return {
		"success": true,
		"page_id": page.get("id", ""),
		"title": page.get("title", ""),
		"index": active_info_panel_index,
		"count": info_panel_pages.size(),
	}


func current_info_panel_page() -> Dictionary:
	if info_panel_pages.is_empty():
		return {}
	active_info_panel_index = clampi(active_info_panel_index, 0, info_panel_pages.size() - 1)
	return info_panel_pages[active_info_panel_index].duplicate(true)


func info_panel_snapshot() -> Dictionary:
	return {
		"active_page": current_info_panel_page(),
		"enabled_pages": info_panel_pages.duplicate(true),
		"active_index": active_info_panel_index,
		"count": info_panel_pages.size(),
	}


func runtime_control_snapshot() -> Dictionary:
	return {
		"auto_tick": auto_tick_enabled,
		"observe_mode": observe_mode_enabled,
		"observe_playback": observe_playback_enabled(),
		"observe_speed": observe_speed_id,
		"observe_speed_multiplier": observe_speed_multiplier(),
	}


func should_submit_auto_tick(delta: float) -> bool:
	if not auto_tick_enabled:
		auto_tick_elapsed_sec = 0.0
		return false
	auto_tick_elapsed_sec += delta
	if auto_tick_elapsed_sec < auto_tick_interval_sec():
		return false
	auto_tick_elapsed_sec = 0.0
	return true


func observe_playback_enabled() -> bool:
	return observe_mode_enabled and auto_tick_enabled


func observe_speed_index(speed_id: String) -> int:
	for index in range(OBSERVE_SPEEDS.size()):
		if str(OBSERVE_SPEEDS[index].get("id", "")) == speed_id:
			return index
	return -1


func observe_speed_multiplier() -> float:
	var index := observe_speed_index(observe_speed_id)
	if index < 0:
		return 1.0
	return maxf(1.0, float(OBSERVE_SPEEDS[index].get("multiplier", 1.0)))


func auto_tick_interval_sec() -> float:
	if not observe_mode_enabled:
		return AUTO_TICK_INTERVAL_SEC
	return maxf(0.01, AUTO_TICK_INTERVAL_SEC / observe_speed_multiplier())
