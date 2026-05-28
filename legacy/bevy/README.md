# Legacy Bevy Launchers

This directory keeps the old Bevy / Rust launch scripts for behavior comparison during the Godot migration.

The archived Rust workspace now lives at `legacy/bevy/rust/`. The legacy batch launchers resolve their Cargo workspace from this directory, so root-level `rust/` is no longer a default project path.

Default development should use the repository root Godot launchers:

```powershell
.\run_godot_game.bat
.\run_godot_editor.bat
.\run_godot_validate.bat
```

Use these legacy launchers only when an old Bevy behavior needs to be compared against the migrated Godot path.

Additional Bevy-only maintenance notes, archived workflow notes, and pre-Godot planning documents live under `legacy/bevy/docs/`.
Archived Bevy runtime config and smoke artifacts live under `legacy/bevy/config/` and `legacy/bevy/smoke-artifacts/`.
