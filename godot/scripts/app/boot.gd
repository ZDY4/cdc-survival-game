extends Control

const MAIN_MENU_SCENE = preload("res://scenes/boot/main_menu.tscn")


func _ready() -> void:
	if get_node_or_null("MainMenu") != null:
		return
	var main_menu := MAIN_MENU_SCENE.instantiate()
	add_child(main_menu)
	print("CDC Survival Game Godot main menu ready")
