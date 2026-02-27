#!/usr/bin/env python3
"""
Simplified Asset Generator - Direct API calls
"""

import sys
sys.path.insert(0, "C:/Users/zdy/.openclaw/workspace/skills/image-generation")

from scripts.image_generator import ImageGenerator
from pathlib import Path
import time

def main():
    print("=" * 60)
    print("CDC Survival Game - Asset Generation (Simplified)")
    print("=" * 60)
    print()
    
    # Initialize generator
    gen = ImageGenerator()
    output_base = Path("G:/project/cdc_survival_game/assets/generated")
    output_base.mkdir(parents=True, exist_ok=True)
    
    # Style
    style = "anime style, cel-shaded, post-apocalyptic, game asset"
    
    # Assets to generate
    assets = [
        # Characters
        ("characters/hero", "female survivor, short hair, tactical vest, determined expression, transparent background", "512x512"),
        ("characters/zombie", "zombie, decaying skin, tattered clothes, transparent background", "512x512"),
        
        # Scenes
        ("scenes/safehouse", "abandoned safehouse interior, night, cozy but eerie, bed and locker, game background", "1280x720"),
        ("scenes/street", "abandoned city street, dusk, destroyed cars, fog, game background", "1280x720"),
        
        # Items
        ("items/knife", "knife weapon, game icon, transparent background", "128x128"),
        ("items/medkit", "first aid kit, medical supplies, game icon, transparent background", "128x128"),
    ]
    
    success = 0
    failed = 0
    
    for i, (path, prompt, size) in enumerate(assets, 1):
        print(f"[{i}/{len(assets)}] Generating: {path}")
        
        try:
            # Build full prompt
            full_prompt = f"{style}, {prompt}"
            
            # Generate
            result = gen.generate(full_prompt, size=size, style="anime")
            
            if result and "url" in result:
                # Download
                import urllib.request
                output_path = output_base / f"{path}.png"
                output_path.parent.mkdir(parents=True, exist_ok=True)
                urllib.request.urlretrieve(result["url"], output_path)
                
                print(f"  [OK] Saved to {output_path}")
                success += 1
            else:
                print(f"  [FAIL] No URL in result: {result}")
                failed += 1
                
        except Exception as e:
            print(f"  [FAIL] Error: {e}")
            failed += 1
        
        # Delay
        time.sleep(3)
        print()
    
    print("=" * 60)
    print(f"Generation Complete: {success} success, {failed} failed")
    print(f"Output: {output_base}")
    print("=" * 60)

if __name__ == "__main__":
    main()
