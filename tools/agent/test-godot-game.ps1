<#
.SYNOPSIS
Runs deterministic Godot game smoke scenarios.

.DESCRIPTION
This script is the repo-local agent entrypoint for Godot runtime smoke checks.
It runs Godot 4.6.3 headless scripts from `godot/scripts/tools/`, captures console
output, and writes a JSON result under `.local/agent-smoke/godot_game`.
It also covers `godot/scripts/app/headless_runner.gd`, the migrated replacement
path for server/headless smoke entrypoints.
When the Scene scenario passes, it also writes `Scene.asset-diagnostics.json`
with map visual, glTF import, and UID baseline diagnostics parsed from the log.

.PARAMETER Scenario
Smoke scenario to run. Use `All` to run every migrated Godot smoke scenario.

.PARAMETER OutputRoot
Directory for console logs and JSON result output. Defaults to `.local/agent-smoke/godot_game`.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-game.ps1

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario All
#>
[CmdletBinding()]
param(
    [ValidateSet(
        "All",
        "MigrationGuard",
        "HeadlessNewGame",
        "HeadlessWorld",
        "MainMenu",
        "Runtime",
        "ContentCLI",
        "ContentEdit",
        "EditorHandoff",
        "ContentEditors",
        "MapReview",
        "FogShader",
        "Door",
        "World",
        "Scene",
        "Overworld",
        "Movement",
        "Vision",
        "AI",
        "Interaction",
        "PlayerInteraction",
        "UI",
        "UIToggle",
        "DialogueUI",
        "DialogueAction",
        "InventoryUI",
        "ContainerUI",
        "JournalUI",
        "SkillsUI",
        "TradeUI",
        "Quest",
        "Combat",
        "Progression",
        "Equipment",
        "CraftingUI",
        "Crafting",
        "Save"
    )]
    [string]$Scenario = "All",

    [string]$OutputRoot,

    [string]$Godot = "D:\godot\godot.cmd"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\agent-smoke\godot_game"
}
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot command not found: $Godot"
}

$scenarioScripts = [ordered]@{
    MigrationGuard   = "res://scripts/tools/mainline_migration_guard.gd"
    HeadlessNewGame  = @{
        Script = "res://scripts/app/headless_runner.gd"
        Args = @("--scenario", "new_game_smoke")
    }
    HeadlessWorld    = @{
        Script = "res://scripts/app/headless_runner.gd"
        Args = @("--scenario", "world_smoke")
    }
    MainMenu         = "res://scripts/tools/main_menu_smoke.gd"
    Runtime           = "res://scripts/tools/runtime_smoke.gd"
    ContentCLI        = "res://scripts/tools/content_cli_smoke.gd"
    ContentEdit       = "res://scripts/tools/content_edit_service_smoke.gd"
    EditorHandoff     = "res://scripts/tools/editor_handoff_smoke.gd"
    ContentEditors    = "res://scripts/tools/content_record_editor_smoke.gd"
    MapReview         = "res://scripts/tools/map_preview_smoke.gd"
    FogShader         = "res://scripts/tools/fog_shader_smoke.gd"
    World             = "res://scripts/tools/world_smoke.gd"
    Scene             = "res://scripts/tools/scene_smoke.gd"
    Overworld         = "res://scripts/tools/overworld_smoke.gd"
    Movement          = "res://scripts/tools/movement_smoke.gd"
    Vision            = "res://scripts/tools/vision_smoke.gd"
    AI                = "res://scripts/tools/ai_smoke.gd"
    Interaction       = "res://scripts/tools/interaction_smoke.gd"
    PlayerInteraction = "res://scripts/tools/player_interaction_smoke.gd"
    UI                = "res://scripts/tools/ui_smoke.gd"
    UIToggle          = "res://scripts/tools/ui_toggle_smoke.gd"
    DialogueUI        = "res://scripts/tools/dialogue_ui_smoke.gd"
    DialogueAction    = "res://scripts/tools/dialogue_action_smoke.gd"
    InventoryUI       = "res://scripts/tools/inventory_ui_smoke.gd"
    ContainerUI       = "res://scripts/tools/container_ui_smoke.gd"
    JournalUI         = "res://scripts/tools/journal_ui_smoke.gd"
    SkillsUI          = "res://scripts/tools/skills_ui_smoke.gd"
    TradeUI           = "res://scripts/tools/trade_ui_smoke.gd"
    Quest             = "res://scripts/tools/quest_smoke.gd"
    Combat            = "res://scripts/tools/combat_smoke.gd"
    Progression       = "res://scripts/tools/progression_smoke.gd"
    Equipment         = "res://scripts/tools/equipment_smoke.gd"
    CraftingUI        = "res://scripts/tools/crafting_ui_smoke.gd"
    Crafting          = "res://scripts/tools/crafting_smoke.gd"
    Save              = "res://scripts/tools/save_smoke.gd"
}

$selected = @()
if ($Scenario -eq "Door") {
    $selected = @("World", "Scene", "Movement", "AI", "Interaction", "PlayerInteraction", "Save")
} elseif ($Scenario -eq "All") {
    $selected = @($scenarioScripts.Keys)
} else {
    $selected = @($Scenario)
}

$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function Export-SceneAssetDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConsoleLog,

        [Parameter(Mandatory = $true)]
        [string]$RunRoot
    )

    if (-not (Test-Path -LiteralPath $ConsoleLog)) {
        return $null
    }

    $rawLog = Get-Content -LiteralPath $ConsoleLog -Raw
    $marker = "scene_smoke passed:"
    $markerIndex = $rawLog.LastIndexOf($marker, [System.StringComparison]::Ordinal)
    if ($markerIndex -lt 0) {
        return $null
    }

    $jsonText = $rawLog.Substring($markerIndex + $marker.Length).Trim()
    try {
        $counts = $jsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        $jsonStart = $jsonText.IndexOf("{", [System.StringComparison]::Ordinal)
        $jsonEnd = $jsonText.LastIndexOf("}", [System.StringComparison]::Ordinal)
        if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) {
            throw "Scene smoke log did not contain parseable JSON after marker '$marker': $ConsoleLog"
        }
        $counts = $jsonText.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json -Depth 100
    }

    $diagnosticsPath = Join-Path $RunRoot "Scene.asset-diagnostics.json"
    $diagnostics = [ordered]@{
        generatedAt = (Get-Date).ToString("o")
        sourceLog = $ConsoleLog
        scenario = "Scene"
        summary = [ordered]@{
            mapSceneCount = $counts.map_scene_count
            allMapDeclaredVisuals = $counts.all_map_declared_visuals
            allMapInstantiatedVisuals = $counts.all_map_instantiated_visuals
            allMapVisualFallbacks = $counts.all_map_visual_fallbacks
            allMapVisualOverlaps = $counts.all_map_visual_overlaps
            allMapVisualAssetPathCount = $counts.all_map_visual_asset_path_count
            allMapVisualSceneReportCount = $counts.all_map_visual_scene_report_count
            gltfAssetCount = $counts.gltf_asset_count
            gltfMeshCount = $counts.gltf_mesh_count
            gltfMaterialCount = $counts.gltf_material_count
            gltfImportUidBaselineCount = $counts.gltf_import_uid_baseline_count
            assetUidSidecarBaselineCount = $counts.asset_uid_sidecar_baseline_count
        }
        mapVisualSceneReports = @($counts.all_map_visual_scene_reports)
        mapVisualAssetPaths = @($counts.all_map_visual_asset_paths)
        gltfAssetDiagnostics = @($counts.gltf_asset_diagnostics)
        gltfImportUidBaseline = @($counts.gltf_import_uid_baseline)
        assetUidSidecarBaseline = @($counts.asset_uid_sidecar_baseline)
        missingOrInvalid = [ordered]@{
            missingExternalBuffers = @($counts.gltf_missing_external_buffers)
            bufferLengthMismatches = @($counts.gltf_buffer_length_mismatches)
            missingImportFiles = @($counts.gltf_missing_import_files)
            importSourceMismatches = @($counts.gltf_import_source_mismatches)
            missingImportUids = @($counts.gltf_missing_import_uids)
            missingImportDestinations = @($counts.gltf_missing_import_destinations)
            duplicateImportUids = @($counts.gltf_duplicate_import_uids)
            invalidUidSidecars = @($counts.asset_invalid_uid_sidecars)
            uidSidecarsMissingResources = @($counts.asset_uid_sidecars_missing_resources)
            duplicateResourceUids = @($counts.asset_duplicate_resource_uids)
        }
    }

    $diagnostics | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $diagnosticsPath
    return $diagnosticsPath
}

$startedAt = Get-Date
$status = "passed"
$results = @()

Push-Location $repoRoot
try {
    foreach ($name in $selected) {
        $scenarioConfig = $scenarioScripts[$name]
        $scriptPath = $scenarioConfig
        $scriptArgs = @()
        if ($scenarioConfig -is [hashtable]) {
            $scriptPath = $scenarioConfig.Script
            $scriptArgs = @($scenarioConfig.Args)
        }
        $consoleLog = Join-Path $runRoot ("{0}.log" -f $name)
        Write-Host "Running Godot smoke scenario '$name' with script '$scriptPath'"
        & $Godot --headless --path godot --script $scriptPath @scriptArgs 2>&1 |
            Tee-Object -FilePath $consoleLog
        $exitCode = $LASTEXITCODE
        $scenarioStatus = if ($exitCode -eq 0) { "passed" } else { "failed" }
        if ($exitCode -ne 0) {
            $status = "failed"
        }
        $assetDiagnostics = $null
        if ($name -eq "Scene" -and $exitCode -eq 0) {
            $assetDiagnostics = Export-SceneAssetDiagnostics -ConsoleLog $consoleLog -RunRoot $runRoot
            if ($assetDiagnostics) {
                Write-Host "Scene asset diagnostics written to $assetDiagnostics"
            }
        }
        $results += [PSCustomObject]@{
            scenario = $name
            script = $scriptPath
            status = $scenarioStatus
            exitCode = $exitCode
            consoleLog = $consoleLog
            assetDiagnostics = $assetDiagnostics
        }
        if ($exitCode -ne 0) {
            break
        }
    }
}
finally {
    Pop-Location
}

$resultPath = Join-Path $runRoot "result.json"
$result = [PSCustomObject]@{
    scenario = $Scenario
    status = $status
    startedAt = $startedAt.ToString("o")
    finishedAt = (Get-Date).ToString("o")
    results = $results
}
$result | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath

if ($status -ne "passed") {
    Write-Error "Godot game smoke failed; see $resultPath"
}

Write-Host "Godot game smoke result written to $resultPath"
