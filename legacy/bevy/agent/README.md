# Legacy Bevy Agent Tools

This directory keeps old Bevy / Rust agent workflows for behavior comparison during the Godot migration.

Default development should use `tools/agent/` Godot tools. Use these only when comparing old behavior:

```powershell
pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Map survivor_outpost_01
pwsh -NoProfile -File legacy/bevy/agent/review-map-visual.ps1 -Map survivor_outpost_01 -NoOpenEditor
pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1 -Scenario WorldInteractionMenu
```

The launchers used by these scripts live in `legacy/bevy/`.
