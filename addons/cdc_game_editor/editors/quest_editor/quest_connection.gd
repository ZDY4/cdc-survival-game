@tool
extends RefCounted
## 任务连接

# 连接信息
var from_quest: String = ""
var to_quest: String = ""
var connection_type: String = "unlock"  # unlock after completion; require as prerequisite

# 视属
var line_color: Color = Color(0.8, 0.8, 0.2)
var line_width: float = 2.0
var is_highlighted: bool = false

func _init(from: String = "", to: String = "", type: String = "unlock"):
	from_quest = from
	to_quest = to
	connection_type = type

func get_color() -> Color:
	match connection_type:
		"unlock":
			return Color(0.2, 0.8, 0.2) if not is_highlighted else Color(0.4, 1.0, 0.4)
		"require":
			return Color(0.8, 0.4, 0.2) if not is_highlighted else Color(1.0, 0.6, 0.4)
		_:
			return line_color

func to_dict() -> Dictionary:
	return {
		"from": from_quest,
		"to": to_quest,
		"type": connection_type
	}

static func from_dict(data: Dictionary) -> RefCounted:
	return load("res://addons/cdc_game_editor/editors/quest_editor/quest_connection.gd").new(
		data.get("from", ""),
		data.get("to", ""),
		data.get("type", "unlock")
	)
