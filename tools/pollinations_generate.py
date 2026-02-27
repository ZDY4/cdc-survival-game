#!/usr/bin/env python3
"""
Asset Generator using Pollinations AI (Free API)
No signup required, completely free
"""

import requests
import urllib.request
from pathlib import Path
import time
import urllib.parse

class PollinationsGenerator:
    """Free image generator using Pollinations AI"""
    
    BASE_URL = "https://image.pollinations.ai/prompt"
    
    def generate(self, prompt, width=512, height=512, seed=None):
        """Generate image from prompt"""
        
        # URL encode the prompt
        encoded_prompt = urllib.parse.quote(prompt)
        
        # Build URL
        url = f"{self.BASE_URL}/{encoded_prompt}?width={width}&height={height}&nologo=true"
        if seed:
            url += f"&seed={seed}"
        
        return {"url": url}
    
    def download_image(self, url, output_path):
        """Download image using requests"""
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        response = requests.get(url, headers=headers, timeout=60)
        response.raise_for_status()
        
        with open(output_path, "wb") as f:
            f.write(response.content)
        
        return True

def main():
    print("=" * 70)
    print("CDC Survival Game - Asset Generation (Pollinations AI)")
    print("Free API - No Signup Required")
    print("=" * 70)
    print()
    
    gen = PollinationsGenerator()
    output_base = Path("G:/project/cdc_survival_game/assets/generated")
    output_base.mkdir(parents=True, exist_ok=True)
    
    # Style for all assets
    style = "anime style, cel shaded, post apocalyptic, dark atmosphere"
    
    # Assets to generate
    assets = [
        # Characters (512x512)
        ("characters/hero_idle", "female survivor, short hair, tactical vest, determined expression, standing pose, transparent background, game sprite", 512, 512),
        ("characters/hero_walk", "female survivor, short hair, tactical vest, walking pose, transparent background, game sprite", 512, 512),
        ("characters/zombie_idle", "zombie, decaying skin, tattered clothes, lifeless eyes, standing pose, transparent background, game sprite", 512, 512),
        ("characters/npc_doctor", "male doctor, white coat, medical bag, glasses, kind face, standing pose, transparent background, game sprite", 512, 512),
        
        # Scenes (1280x720)
        ("scenes/safehouse", "abandoned safehouse interior, night, cozy but eerie, bed and locker, lamp light, post apocalyptic, game background", 1280, 720),
        ("scenes/street", "abandoned city street, dusk, destroyed cars, fog, debris, ruined buildings, post apocalyptic, game background", 1280, 720),
        ("scenes/hospital", "hospital corridor, night, horror atmosphere, medical equipment, blood stains, broken lights, post apocalyptic", 1280, 720),
        
        # Items (128x128)
        ("items/weapon/knife", "combat knife, weapon, game item icon, transparent background", 128, 128),
        ("items/weapon/pistol", "handgun pistol, weapon, game item icon, transparent background", 128, 128),
        ("items/medical/bandage", "medical bandage roll, first aid, game item icon, transparent background", 128, 128),
        ("items/medical/first_aid_kit", "first aid kit box, red cross, medical supplies, game item icon, transparent background", 128, 128),
        ("items/food/canned_food", "canned food, survival ration, game item icon, transparent background", 128, 128),
        ("items/food/water_bottle", "water bottle, clean water, survival, game item icon, transparent background", 128, 128),
        ("items/material/scrap_metal", "scrap metal pieces, crafting material, game item icon, transparent background", 128, 128),
        ("items/key/key_card", "electronic key card, access card, game item icon, transparent background", 128, 128),
    ]
    
    success = 0
    failed = 0
    
    for i, (path, prompt, width, height) in enumerate(assets, 1):
        print(f"[{i}/{len(assets)}] Generating: {path}")
        
        try:
            # Build full prompt
            full_prompt = f"{style}, {prompt}"
            
            # Generate URL
            result = gen.generate(full_prompt, width=width, height=height, seed=42)
            
            if result and "url" in result:
                url = result["url"]
                
                # Download
                output_path = output_base / f"{path}.png"
                output_path.parent.mkdir(parents=True, exist_ok=True)
                
                print(f"  Downloading...")
                gen.download_image(url, output_path)
                
                # Check file size
                file_size = output_path.stat().st_size
                if file_size > 1000:  # At least 1KB
                    print(f"  [OK] {path}.png ({file_size/1024:.1f} KB)")
                    success += 1
                else:
                    print(f"  [FAIL] File too small ({file_size} bytes)")
                    failed += 1
            else:
                print(f"  [FAIL] No URL generated")
                failed += 1
                
        except Exception as e:
            print(f"  [FAIL] Error: {e}")
            failed += 1
        
        # Delay to avoid rate limiting
        time.sleep(2)
        print()
    
    print("=" * 70)
    print(f"Generation Complete: {success} success, {failed} failed")
    print(f"Output: {output_base}")
    print("=" * 70)

if __name__ == "__main__":
    main()
