extends Node

func _ready():
    print("=== Godot Asset Import Check ===")
    
    var assets_dir = "res://assets/generated"
    var asset_files = []
    
    # List all image files
    var dir = DirAccess.open(assets_dir)
    if dir:
        dir.list_dir_begin()
        var file = dir.get_next()
        while file != "":
            if file.ends_with(".png"):
                asset_files.append(assets_dir + "/" + file)
            elif !file.begins_with("."):
                # Recursively check subdirectories
                # (Godot's DirAccess doesn't have recursive method, need to implement)
                pass
            file = dir.get_next()
    
    # Print all assets found
    print("\nFound assets:")
    for asset in asset_files:
        print("  " + asset)
    
    print("\n=== Integration complete ===")
