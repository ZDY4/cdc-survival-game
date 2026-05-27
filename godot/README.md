# CDC Survival Game Godot Migration

This is the Godot 4.6.3 migration workspace for the project.

Run headless validation from the repository root:

```powershell
D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/validate_all.gd
```

Open the project:

```powershell
D:\godot\godot.cmd --path godot
```

During migration, source content remains in the repository-level `data/` directory. Godot scripts read that data in place so the old Rust/Bevy implementation can remain as a behavior baseline until the migration is complete.
