@tool
extends EditorPlugin


func _enter_tree() -> void:
	# 迁移早期只注册插件壳，具体编辑器在内容服务稳定后接入。
	print("CDC Game Editor plugin loaded")


func _exit_tree() -> void:
	pass
