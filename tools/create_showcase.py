from PIL import Image, ImageDraw, ImageFont
import os

# 创建一个展示图，展示所有生成的资源
width, height = 1280, 720
img = Image.new('RGB', (width, height), color='#1a1a2e')
draw = ImageDraw.Draw(img)

# 标题
draw.text((width//2 - 200, 20), "CDC Survival Game - AI Generated Assets", fill='white')
draw.text((width//2 - 150, 50), "Anime Style Core Assets Showcase", fill='#aaa')

# 加载并放置生成的资源
assets_base = "G:/project/cdc_survival_game/assets/generated"

# 场景预览 (顶部中央)
try:
    safehouse = Image.open(f"{assets_base}/scenes/safehouse.png")
    safehouse = safehouse.resize((400, 225))
    img.paste(safehouse, (440, 100))
    draw.text((440, 330), "Scene: Safehouse (1280x720)", fill='white')
except Exception as e:
    draw.rectangle([440, 100, 840, 325], fill='#2a2a4e', outline='white')
    draw.text((540, 200), "Safehouse\nScene", fill='white')

# 角色 (左侧)
char_y = 380
try:
    hero = Image.open(f"{assets_base}/characters/hero_idle.png")
    hero = hero.resize((100, 100))
    img.paste(hero, (100, char_y), hero if hero.mode == 'RGBA' else None)
    draw.text((100, char_y+110), "Hero", fill='white')
except:
    draw.ellipse([100, char_y, 200, char_y+100], fill='#c65d2a')
    draw.text((130, char_y+110), "Hero", fill='white')

try:
    zombie = Image.open(f"{assets_base}/characters/zombie_idle.png")
    zombie = zombie.resize((100, 100))
    img.paste(zombie, (250, char_y), zombie if zombie.mode == 'RGBA' else None)
    draw.text((250, char_y+110), "Zombie", fill='white')
except:
    draw.ellipse([250, char_y, 350, char_y+100], fill='#3d5c2a')
    draw.text((270, char_y+110), "Zombie", fill='white')

# 物品 (右侧)
item_x = 900
item_y = 380
try:
    knife = Image.open(f"{assets_base}/items/knife.png")
    knife = knife.resize((64, 64))
    img.paste(knife, (item_x, item_y), knife if knife.mode == 'RGBA' else None)
    draw.text((item_x, item_y+70), "Knife", fill='white')
except:
    draw.rectangle([item_x, item_y, item_x+64, item_y+64], fill='gray')
    draw.text((item_x, item_y+70), "Knife", fill='white')

try:
    medkit = Image.open(f"{assets_base}/items/medkit.png")
    medkit = medkit.resize((64, 64))
    img.paste(medkit, (item_x+100, item_y), medkit if medkit.mode == 'RGBA' else None)
    draw.text((item_x+100, item_y+70), "Medkit", fill='white')
except:
    draw.rectangle([item_x+100, item_y, item_x+164, item_y+64], fill='red')
    draw.text((item_x+100, item_y+70), "Medkit", fill='white')

# UI元素 (底部)
ui_y = 550
draw.rectangle([100, ui_y, 300, ui_y+50], fill='#4a4a6e', outline='white')
draw.text((140, ui_y+15), "Button Normal", fill='white')

draw.rectangle([350, ui_y, 550, ui_y+30], fill='#8a2a2a', outline='white')
draw.text((360, ui_y+8), "Health Bar", fill='white')

# 统计信息
draw.text((900, 500), "Asset Statistics:", fill='white')
draw.text((900, 525), "• Characters: 4", fill='#aaa')
draw.text((900, 545), "• Scenes: 3", fill='#aaa')
draw.text((900, 565), "• Items: 4", fill='#aaa')
draw.text((900, 585), "• UI Elements: 8", fill='#aaa')
draw.text((900, 615), "Total: 19 assets", fill='green')

# 保存
output_path = "G:/project/cdc_survival_game/assets/generated_showcase.png"
img.save(output_path)
print(f"Showcase image saved to: {output_path}")
