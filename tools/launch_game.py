import subprocess
import time
import os

print("="*60)
print("CDC Survival Game - Auto Launcher")
print("="*60)

godot_path = r"D:\godot\Godot_v4.6-stable_win64.exe"
project_path = r"G:\project\cdc_survival_game"

if not os.path.exists(godot_path):
    print("ERROR: Godot not found at", godot_path)
    exit(1)

print("Starting game...")
print("Godot:", godot_path)
print("Project:", project_path)
print("")

# Start the game
process = subprocess.Popen(
    [godot_path, "--path", project_path, "--editor"],
    creationflags=subprocess.CREATE_NEW_CONSOLE
)

print("Game process started (PID:", process.pid, ")")
print("")
print("Please wait 5 seconds for the game to load...")
time.sleep(5)
print("")
print("="*60)
print("Game should be running now!")
print("")
print("To test the game:")
print("1. Wait for Godot editor to fully load")
print("2. Press F5 to run the game")
print("3. Click 'Start Game' in the main menu")
print("4. Test the bed (sleep), door (go to street)")
print("5. Press ESC to quit game, then close editor")
print("="*60)

# Keep the script running
input("\nPress Enter to close this window...")
