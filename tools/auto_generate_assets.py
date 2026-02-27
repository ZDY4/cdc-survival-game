#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Automated AI Asset Generation Script
Anime Style | Core Assets | Zero Human Intervention
"""

import sys
import os
import json
import time
from pathlib import Path

# Add image-generation skill to path
sys.path.insert(0, "C:/Users/zdy/.openclaw/workspace/skills/image-generation")

from generators.character_generator import CharacterGenerator
from generators.scene_generator import SceneGenerator
from generators.item_generator import ItemGenerator

class AutomatedAssetGenerator:
    """Automated Asset Generator"""
    
    def __init__(self, config_path):
        self.config = self._load_config(config_path)
        self.output_base = Path(self.config["output_base"])
        self.style_prompt = self.config["style_prompt"]
        self.stats = {
            "total": 0,
            "success": 0,
            "failed": 0,
            "by_category": {}
        }
        
        # Ensure output directory exists
        self.output_base.mkdir(parents=True, exist_ok=True)
        
        # Initialize generators
        try:
            self.char_gen = CharacterGenerator()
            self.scene_gen = SceneGenerator()
            self.item_gen = ItemGenerator()
            print("Generators initialized successfully")
        except Exception as e:
            print(f"Warning: Could not initialize generators: {e}")
            print("Will use fallback generation method")
            self.char_gen = None
            self.scene_gen = None
            self.item_gen = None
        
    def _load_config(self, path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    
    def generate_all(self):
        """Generate all assets"""
        print("=" * 70)
        print("CDC Survival Game - AI Asset Generation")
        print("Style: Anime | Scope: Core Assets")
        print("=" * 70)
        print()
        
        # 1. Generate Characters
        self._generate_characters()
        
        # 2. Generate Scenes
        self._generate_scenes()
        
        # 3. Generate Items
        self._generate_items()
        
        # 4. Generate UI
        self._generate_ui()
        
        # 5. Show statistics
        self._show_stats()
        
    def _generate_characters(self):
        """Generate character assets"""
        print("[Phase 1/4] Generating Characters...")
        print("-" * 50)
        
        chars = self.config.get("characters", [])
        self.stats["by_category"]["characters"] = {"total": 0, "success": 0}
        
        for char in chars:
            name = char["name"]
            archetype = char["archetype"]
            poses = char.get("poses", ["idle"])
            
            print(f"  Character: {name} ({archetype})")
            
            for pose in poses:
                try:
                    # Build prompt
                    prompt = self._build_character_prompt(char, pose)
                    
                    # Output path
                    output_dir = self.output_base / "characters" / name
                    output_dir.mkdir(parents=True, exist_ok=True)
                    output_file = output_dir / f"{pose}.png"
                    
                    # Generate image using image_generation module
                    if self.char_gen:
                        result = self.char_gen.generate(
                            archetype=archetype,
                            gender=char.get("gender", "any"),
                            features=char.get("features", []),
                            style="anime",
                            pose=pose
                        )
                    else:
                        # Fallback: use direct API
                        result = self._generate_with_api(prompt, "512x512")
                    
                    # Save image
                    if result:
                        if isinstance(result, dict) and "url" in result:
                            self._download_image(result["url"], output_file)
                        elif isinstance(result, str):
                            # Result is already a file path
                            import shutil
                            shutil.copy(result, output_file)
                        
                        print(f"    [OK] {pose}.png")
                        self.stats["success"] += 1
                        self.stats["by_category"]["characters"]["success"] += 1
                    else:
                        print(f"    [FAIL] {pose}.png - Generation failed")
                        self.stats["failed"] += 1
                    
                    self.stats["total"] += 1
                    self.stats["by_category"]["characters"]["total"] += 1
                    
                    # Delay to avoid API limits
                    time.sleep(2)
                    
                except Exception as e:
                    print(f"    [FAIL] {pose}.png - Error: {str(e)}")
                    self.stats["failed"] += 1
        
        print()
    
    def _generate_scenes(self):
        """Generate scene assets"""
        print("[Phase 2/4] Generating Scenes...")
        print("-" * 50)
        
        scenes = self.config.get("scenes", [])
        self.stats["by_category"]["scenes"] = {"total": 0, "success": 0}
        
        for scene in scenes:
            name = scene["name"]
            print(f"  Scene: {name}")
            
            try:
                # Build prompt
                prompt = self._build_scene_prompt(scene)
                
                # Output path
                output_dir = self.output_base / "scenes"
                output_dir.mkdir(parents=True, exist_ok=True)
                output_file = output_dir / f"{name}.png"
                
                # Generate scene
                if self.scene_gen:
                    result = self.scene_gen.generate(
                        location=scene["location"],
                        time=scene.get("time", "day"),
                        mood=scene.get("mood", "neutral"),
                        style="anime"
                    )
                else:
                    result = self._generate_with_api(prompt, "1280x720")
                
                # Save image
                if result:
                    if isinstance(result, dict) and "url" in result:
                        self._download_image(result["url"], output_file)
                    elif isinstance(result, str):
                        import shutil
                        shutil.copy(result, output_file)
                    
                    print(f"    [OK] {name}.png")
                    self.stats["success"] += 1
                    self.stats["by_category"]["scenes"]["success"] += 1
                else:
                    print(f"    [FAIL] {name}.png - Generation failed")
                    self.stats["failed"] += 1
                
                self.stats["total"] += 1
                self.stats["by_category"]["scenes"]["total"] += 1
                
                # Delay to avoid API limits
                time.sleep(2)
                
            except Exception as e:
                print(f"    [FAIL] {name}.png - Error: {str(e)}")
                self.stats["failed"] += 1
        
        print()
    
    def _generate_items(self):
        """Generate item assets"""
        print("[Phase 3/4] Generating Items...")
        print("-" * 50)
        
        items = self.config.get("items", [])
        self.stats["by_category"]["items"] = {"total": 0, "success": 0}
        
        for item in items:
            name = item["name"]
            category = item["category"]
            print(f"  Item: {name} ({category})")
            
            try:
                # Output path
                output_dir = self.output_base / "items" / category
                output_dir.mkdir(parents=True, exist_ok=True)
                output_file = output_dir / f"{name}.png"
                
                # Generate item
                if self.item_gen:
                    result = self.item_gen.generate(
                        name=name,
                        category=category,
                        rarity=item.get("rarity", "common"),
                        style="game_icon",
                        size=item.get("size", "128x128")
                    )
                else:
                    prompt = f"game item icon, {category}, {name}, transparent background, 2D"
                    result = self._generate_with_api(prompt, "128x128")
                
                # Save image
                if result:
                    if isinstance(result, dict) and "url" in result:
                        self._download_image(result["url"], output_file)
                    elif isinstance(result, str):
                        import shutil
                        shutil.copy(result, output_file)
                    
                    print(f"    [OK] {name}.png")
                    self.stats["success"] += 1
                    self.stats["by_category"]["items"]["success"] += 1
                else:
                    print(f"    [FAIL] {name}.png - Generation failed")
                    self.stats["failed"] += 1
                
                self.stats["total"] += 1
                self.stats["by_category"]["items"]["total"] += 1
                
                # Delay to avoid API limits
                time.sleep(1)
                
            except Exception as e:
                print(f"    [FAIL] {name}.png - Error: {str(e)}")
                self.stats["failed"] += 1
        
        print()
    
    def _generate_ui(self):
        """Generate UI assets"""
        print("[Phase 4/4] Generating UI Elements...")
        print("-" * 50)
        
        ui_elements = self.config.get("ui_elements", [])
        self.stats["by_category"]["ui"] = {"total": 0, "success": 0}
        
        # Simplified UI generation - use PIL to create placeholder images
        output_dir = self.output_base / "ui"
        output_dir.mkdir(parents=True, exist_ok=True)
        
        for ui in ui_elements:
            name = ui["name"]
            print(f"  UI: {name}")
            
            try:
                # Create placeholder image using PIL
                from PIL import Image, ImageDraw
                
                size = ui.get("size", "256x64").split("x")
                width, height = int(size[0]), int(size[1])
                
                # Create image
                img = Image.new("RGBA", (width, height), (30, 30, 30, 255))
                draw = ImageDraw.Draw(img)
                
                # Draw different styles based on type
                if ui["type"] == "button":
                    if ui.get("state") == "hover":
                        draw.rectangle([0, 0, width-1, height-1], fill=(60, 60, 60, 255), outline=(100, 100, 100, 255))
                    elif ui.get("state") == "pressed":
                        draw.rectangle([0, 0, width-1, height-1], fill=(20, 20, 20, 255), outline=(80, 80, 80, 255))
                    else:  # normal
                        draw.rectangle([0, 0, width-1, height-1], fill=(40, 40, 40, 255), outline=(100, 100, 100, 255))
                elif ui["type"] == "panel":
                    draw.rectangle([0, 0, width-1, height-1], fill=(25, 25, 25, 240), outline=(80, 80, 80, 255))
                elif ui["type"] == "bar":
                    if "fill" in name:
                        draw.rectangle([0, 0, width-1, height-1], fill=(200, 50, 50, 255))
                    else:
                        draw.rectangle([0, 0, width-1, height-1], fill=(50, 50, 50, 255), outline=(100, 100, 100, 255))
                
                # Save
                output_file = output_dir / f"{name}.png"
                img.save(output_file)
                
                print(f"    [OK] {name}.png")
                self.stats["success"] += 1
                self.stats["by_category"]["ui"]["success"] += 1
                
            except Exception as e:
                print(f"    [FAIL] {name}.png - Error: {str(e)}")
                self.stats["failed"] += 1
            
            self.stats["total"] += 1
            self.stats["by_category"]["ui"]["total"] += 1
        
        print()
    
    def _generate_with_api(self, prompt, size):
        """Direct API call fallback"""
        try:
            from scripts.image_generator import ImageGenerator
            gen = ImageGenerator()
            return gen.generate(prompt, size=size, style="anime")
        except Exception as e:
            print(f"    API call failed: {e}")
            return None
    
    def _build_character_prompt(self, char, pose):
        """Build character prompt"""
        features = ", ".join(char.get("features", []))
        return f"{self.style_prompt}, {char['archetype']}, {char.get('gender', '')}, {features}, {pose} pose, transparent background, game sprite"
    
    def _build_scene_prompt(self, scene):
        """Build scene prompt"""
        elements = ", ".join(scene.get("elements", []))
        return f"{self.style_prompt}, {scene['location']}, {scene.get('time', 'day')}, {scene.get('mood', 'neutral')}, {elements}, game background"
    
    def _download_image(self, url, output_path):
        """Download image"""
        import urllib.request
        urllib.request.urlretrieve(url, output_path)
    
    def _show_stats(self):
        """Show statistics"""
        print("=" * 70)
        print("Generation Statistics")
        print("=" * 70)
        print(f"Total: {self.stats['total']}")
        print(f"Success: {self.stats['success']} [OK]")
        print(f"Failed: {self.stats['failed']} [FAIL]")
        print()
        print("By Category:")
        for category, data in self.stats["by_category"].items():
            success_rate = (data["success"] / data["total"] * 100) if data["total"] > 0 else 0
            print(f"  {category}: {data['success']}/{data['total']} ({success_rate:.0f}%)")
        print()
        print(f"Output Directory: {self.output_base}")
        print("=" * 70)
        print("Asset Generation Complete!")

if __name__ == "__main__":
    config_path = "G:/project/cdc_survival_game/tools/asset_generation_config.json"
    generator = AutomatedAssetGenerator(config_path)
    generator.generate_all()
