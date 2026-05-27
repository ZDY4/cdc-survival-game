extends Control


func _ready() -> void:
	# 迁移期入口先保持极简，避免 UI 先行绑定尚未端口完成的运行时。
	print("CDC Survival Game Godot migration boot scene ready")
