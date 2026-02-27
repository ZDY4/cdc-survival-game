#!/usr/bin/env python3
"""
Godot 4 Asset Integration Script
Automatically configures imported images and creates basic TSCN scenes
"""

import os
from pathlib import Path
import json

class GodotAssetIntegrator:
    """Integrate generated assets into Godot project"""
    
    def __init__(self, project_path, assets_dir="assets/generated"):
        self.project_path = Path(project_path)
        self.assets_dir = Path(assets_dir)
        
        # Godot import configuration templates
        self.templates = {
            "character": {
                "importer": "texture",
                "type": "CompressedTexture2D",
                "params": {
                    "compress/mode": 1,  # Lossless
                    "compress/high_quality": True,
                    "compress/lossy_quality": 0.7,
                    "detect_3d": False,
                    "flags/repeat": False,
                    "flags/filter": True,
                    "flags/mipmaps": False
                }
            },
            "scene": {
                "importer": "texture",
                "type": "CompressedTexture2D",
                "params": {
                    "compress/mode": 0,  # Lossy
                    "compress/high_quality": True,
                    "compress/lossy_quality": 0.7,
                    "detect_3d": False,
                    "flags/repeat": False,
                    "flags/filter": True,
                    "flags/mipmaps": False
                }
            },
            "item": {
                "importer": "texture",
                "type": "CompressedTexture2D",
                "params": {
                    "compress/mode": 1,  # Lossless
                    "compress/high_quality": True,
                    "compress/lossy_quality": 0.7,
                    "detect_3d": False,
                    "flags/repeat": False,
                    "flags/filter": True,
                    "flags/mipmaps": False
                }
            },
            "ui": {
                "importer": "texture",
                "type": "CompressedTexture2D",
                "params": {
                    "compress/mode": 1,  # Lossless
                    "compress/high_quality": True,
                    "compress/lossy_quality": 0.7,
                    "detect_3d": False,
                    "flags/repeat": False,
                    "flags/filter": True,
                    "flags/mipmaps": False
                }
            }
        }
    
    def create_import_config(self, texture_path, config_type):
        """Create .import config file"""
        config_path = str(texture_path) + ".import"
        
        with open(config_path, "w", encoding="utf-8") as f:
            f.write(self._generate_import_config(texture_path, config_type))
        
        return config_path
    
    def _generate_import_config(self, texture_path, config_type):
        """Generate import configuration"""
        template = self.templates.get(config_type, self.templates["ui"])
        
        config = f"""[remap]

importer="{template['importer']}"
type="{template['type']}"
uid="uid://{self._generate_uid()}"
path="res://.godot/imported/{texture_path.name}-{self._generate_hash(texture_path)}.ctex"

[deps]

source_file="res://assets/generated/{texture_path.relative_to(self.assets_dir)}"

[params]

compress/mode={template['params']['compress/mode']}
compress/high_quality={str(template['params']['compress/high_quality']).lower()}
compress/lossy_quality={template['params']['compress/lossy_quality']}
detect_3d={str(template['params']['detect_3d']).lower()}
flags/repeat={str(template['params']['flags/repeat']).lower()}
flags/filter={str(template['params']['flags/filter']).lower()}
flags/mipmaps={str(template['params']['flags/mipmaps']).lower()}
"""
        
        return config
    
    def create_character_scene(self, character_name, poses):
        """Create character scene (Node2D)"""
        scene_dir = self.assets_dir / "characters" / character_name
        
        scene_content = """[gd_scene load_steps=1 format=3 uid="uid://{uid}"]

[node name="{name}" type="Node2D"]
""".format(
            uid=self._generate_uid(),
            name=character_name
        )
        
        scene_path = scene_dir / f"{character_name}.tscn"
        with open(scene_path, "w", encoding="utf-8") as f:
            f.write(scene_content)
        
        return scene_path
    
    def create_item_scene(self, item_name, texture_path):
        """Create item scene (Sprite2D)"""
        item_dir = self.assets_dir / "items"
        
        scene_content = f"""[gd_scene load_steps=2 format=3 uid="uid://{self._generate_uid()}"]

[ext_resource type="Texture2D" uid="uid://{self._generate_uid()}" path="res://assets/generated/items/{item_name}.png" id="1_item"]

[node name="{item_name}" type="Sprite2D"]
texture = ExtResource("1_item")
""".format(
            item_name=item_name
        )
        
        scene_path = item_dir / f"{item_name}.tscn"
        with open(scene_path, "w", encoding="utf-8") as f:
            f.write(scene_content)
        
        return scene_path
    
    def create_scene_background(self, scene_name, texture_path):
        """Create scene background"""
        scene_dir = self.assets_dir / "scenes"
        
        scene_content = f"""[gd_scene load_steps=2 format=3 uid="uid://{self._generate_uid()}"]

[ext_resource type="Texture2D" uid="uid://{self._generate_uid()}" path="res://assets/generated/scenes/{scene_name}.png" id="1_background"]

[node name="{scene_name}" type="Node2D"]

[node name="Background" type="Sprite2D" parent="."]
texture = ExtResource("1_background")
position = Vector2(640, 360)
centered = true
""".format(
            scene_name=scene_name
        )
        
        scene_path = scene_dir / f"{scene_name}.tscn"
        with open(scene_path, "w", encoding="utf-8") as f:
            f.write(scene_content)
        
        return scene_path
    
    def integrate_all(self):
        """Integrate all generated assets"""
        print("=" * 70)
        print("Godot 4 Asset Integration")
        print("=" * 70)
        print()
        
        # Characters
        print("1/4 - Integrating Characters")
        character_dir = self.assets_dir / "characters"
        if character_dir.exists():
            for img_file in character_dir.glob("*.png"):
                name = img_file.stem
                self.create_import_config(img_file, "character")
        
        # Scenes
        print("2/4 - Integrating Scenes")
        scene_dir = self.assets_dir / "scenes"
        if scene_dir.exists():
            for img_file in scene_dir.glob("*.png"):
                self.create_import_config(img_file, "scene")
                scene_name = img_file.stem
                self.create_scene_background(scene_name, img_file)
        
        # Items
        print("3/4 - Integrating Items")
        item_dir = self.assets_dir / "items"
        if item_dir.exists():
            for img_file in item_dir.glob("*.png"):
                self.create_import_config(img_file, "item")
                item_name = img_file.stem
                self.create_item_scene(item_name, img_file)
        
        # UI
        print("4/4 - Integrating UI")
        ui_dir = self.assets_dir / "ui"
        if ui_dir.exists():
            for img_file in ui_dir.glob("*.png"):
                self.create_import_config(img_file, "ui")
        
        print()
        print("=" * 70)
        print("Asset integration complete!")
        print()
        print("Generated files:")
        self._list_generated()
    
    def _generate_uid(self):
        import uuid
        return str(uuid.uuid4()).replace("-", "")[:16]
    
    def _generate_hash(self, file_path):
        import hashlib
        with open(file_path, "rb") as f:
            return hashlib.md5(f.read()).hexdigest()[:16]
    
    def _list_generated(self):
        import os
        count = 0
        for ext in [".import", ".tscn"]:
            for file in self.assets_dir.rglob(f"*{ext}"):
                print(f"  {file}")
                count += 1
        
        print(f"\nTotal integration files: {count}")
    
if __name__ == "__main__":
    integrator = GodotAssetIntegrator(
        "G:/project/cdc_survival_game",
        "G:/project/cdc_survival_game/assets/generated"
    )
    integrator.integrate_all()
