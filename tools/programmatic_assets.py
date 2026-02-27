#!/usr/bin/env python3
"""
Programmatic Asset Generator - Fallback for API issues
Creates stylized placeholders with Python imaging library
"""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import random

class ProgrammaticGenerator:
    """Creates stylized asset placeholders programmatically"""
    
    def __init__(self, base_dir):
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(parents=True, exist_ok=True)
    
    def create_character_sprite(self, path, name, archetype, color_scheme):
        """Create character sprite"""
        img = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        
        # Background glow
        bg_color = color_scheme["bg"]
        draw.ellipse([50, 100, 462, 450], fill=bg_color)
        
        # Body silhouette
        body_color = color_scheme["body"]
        draw.ellipse([200, 200, 312, 400], fill=body_color)
        
        # Head
        head_color = color_scheme["head"]
        draw.ellipse([225, 120, 287, 182], fill=head_color)
        
        # Eyes
        eye_color = color_scheme["eyes"]
        draw.ellipse([240, 140, 252, 152], fill=eye_color)
        draw.ellipse([258, 140, 270, 152], fill=eye_color)
        
        # Mouth
        draw.line([245, 165, 265, 165], fill=(255, 255, 255), width=2)
        
        # Weapon (for survivors/enemies)
        if archetype in ["hero", "raider"]:
            draw.line([280, 250, 400, 300], fill=(100, 100, 100), width=10)
        
        # Save
        output_path = self.base_dir / path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        img.save(output_path, "PNG")
        
        return output_path
    
    def create_scene(self, path, name, color_scheme):
        """Create scene background"""
        img = Image.new("RGBA", (1280, 720), color_scheme["bg"])
        draw = ImageDraw.Draw(img)
        
        # Ground
        draw.rectangle([0, 500, 1280, 720], fill=color_scheme["ground"])
        
        # Building silhouettes
        for i in range(3):
            width = random.randint(100, 200)
            height = random.randint(200, 400)
            x = 100 + i * 400
            y = 500 - height
            draw.rectangle([x, y, x + width, 500], fill=color_scheme["building"])
        
        # Debris
        for _ in range(20):
            x = random.randint(0, 1280)
            y = random.randint(500, 650)
            w = random.randint(5, 20)
            h = random.randint(2, 5)
            draw.rectangle([x, y, x + w, y + h], fill=color_scheme["debris"])
        
        # Save
        output_path = self.base_dir / path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        img.save(output_path, "PNG")
        
        return output_path
    
    def create_item_icon(self, path, name, category, color_scheme):
        """Create item icon"""
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        
        # Background circle
        draw.ellipse([20, 20, 108, 108], fill=color_scheme["bg"])
        
        # Item shape based on category
        if category == "weapon":
            draw.line([40, 64, 88, 64], fill=(255, 255, 255), width=8)
        elif category == "medical":
            draw.polygon([(64, 20), (84, 40), (64, 60), (44, 40)], fill=(255, 0, 0))
        elif category == "food":
            draw.ellipse([44, 44, 84, 84], fill=(255, 255, 0))
        elif category == "key":
            draw.rectangle([50, 30, 78, 98], fill=(255, 215, 0))
            draw.line([64, 25, 64, 30], fill=(255, 215, 0), width=3)
        
        # Save
        output_path = self.base_dir / path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        img.save(output_path, "PNG")
        
        return output_path
    
    def create_ui_button(self, path, state, width, height):
        """Create UI button"""
        colors = {
            "normal": {"bg": (80, 80, 80), "border": (150, 150, 150)},
            "hover": {"bg": (120, 120, 120), "border": (200, 200, 200)},
            "pressed": {"bg": (50, 50, 50), "border": (100, 100, 100)},
        }
        
        img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
        draw = ImageDraw.Draw(img)
        
        color = colors[state]
        
        # Button background
        draw.rectangle([0, 0, width - 1, height - 1], fill=color["bg"], outline=color["border"], width=2)
        
        # Highlight
        draw.line([2, 2, width - 3, 2], fill=(255, 255, 255))
        draw.line([2, 2, 2, height - 3], fill=(255, 255, 255))
        
        # Save
        output_path = self.base_dir / path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        img.save(output_path, "PNG")
        
        return output_path

def main():
    print("=" * 70)
    print("CDC Survival Game - Asset Generation (Programmatic)")
    print("Creating placeholder assets with stylized designs")
    print("=" * 70)
    print()
    
    generator = ProgrammaticGenerator("G:/project/cdc_survival_game/assets/generated")
    
    # Color schemes for different archetypes
    color_schemes = {
        "hero": {"bg": (200, 100, 50, 150), "body": (100, 150, 200), "head": (150, 100, 50), "eyes": (255, 255, 255)},
        "zombie": {"bg": (50, 150, 50, 150), "body": (50, 100, 50), "head": (20, 60, 20), "eyes": (255, 200, 0)},
        "npc": {"bg": (100, 100, 150, 150), "body": (100, 150, 100), "head": (150, 100, 100), "eyes": (0, 0, 0)},
        "raider": {"bg": (150, 50, 50, 150), "body": (100, 50, 50), "head": (150, 20, 20), "eyes": (255, 255, 0)},
    }
    
    # Create assets
    print("1/4 - Creating Characters...")
    generator.create_character_sprite("characters/hero_idle.png", "hero", "hero", color_schemes["hero"])
    generator.create_character_sprite("characters/hero_walk.png", "hero", "hero", color_schemes["hero"])
    generator.create_character_sprite("characters/zombie_idle.png", "zombie", "zombie", color_schemes["zombie"])
    generator.create_character_sprite("characters/npc_doctor.png", "doctor", "npc", color_schemes["npc"])
    
    print("2/4 - Creating Scenes...")
    generator.create_scene("scenes/safehouse.png", "Safehouse", {
        "bg": (20, 25, 40),
        "ground": (40, 35, 45),
        "building": (80, 85, 100),
        "debris": (60, 65, 75)
    })
    generator.create_scene("scenes/street.png", "Street", {
        "bg": (40, 45, 60),
        "ground": (60, 55, 65),
        "building": (100, 105, 120),
        "debris": (80, 85, 95)
    })
    generator.create_scene("scenes/hospital.png", "Hospital", {
        "bg": (60, 75, 80),
        "ground": (80, 75, 85),
        "building": (120, 125, 140),
        "debris": (100, 105, 115)
    })
    
    print("3/4 - Creating Items...")
    generator.create_item_icon("items/knife.png", "Knife", "weapon", {"bg": (100, 50, 20)})
    generator.create_item_icon("items/medkit.png", "MedKit", "medical", {"bg": (200, 50, 50)})
    generator.create_item_icon("items/ration.png", "Ration", "food", {"bg": (50, 100, 50)})
    generator.create_item_icon("items/keycard.png", "KeyCard", "key", {"bg": (200, 150, 50)})
    
    print("4/4 - Creating UI Elements...")
    generator.create_ui_button("ui/button_normal.png", "normal", 200, 60)
    generator.create_ui_button("ui/button_hover.png", "hover", 200, 60)
    generator.create_ui_button("ui/button_pressed.png", "pressed", 200, 60)
    
    print()
    print("=" * 70)
    print("Asset Generation Complete!")
    print(f"Output: {generator.base_dir}")
    
    # Count generated files
    import os
    total_files = len(list(generator.base_dir.rglob("*.png")))
    print(f"Total files: {total_files}")
    print("=" * 70)

if __name__ == "__main__":
    main()
