# CDC Survival Game Godot Migration

This is the Godot 4.6.3 migration workspace for the project.

Run the migrated Godot game from the repository root:

```powershell
.\run_godot_game.bat
```

Open the Godot editor:

```powershell
.\run_godot_editor.bat
```

Run headless validation:

```powershell
.\run_godot_validate.bat
```

The underlying validation command is:

```powershell
D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/validate_all.gd
```

The underlying project launch command is:

```powershell
D:\godot\godot.cmd --path godot
```

Map layouts now live in `godot/scenes/maps/*.tscn` and are loaded by the Godot runtime. Non-map source content remains in the repository-level `data/` directory. `data/maps/*.json` is kept as a migration compatibility backup, not the future map authoring path.
