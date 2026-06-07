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
with map visual, scene resource reference, glTF import, and UID baseline
diagnostics parsed from the log.

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

function Compare-UidBaselineEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [array]$Expected,

        [Parameter(Mandatory = $true)]
        [array]$Actual,

        [switch]$CompareSidecarPath
    )

    $mismatches = @()
    $expectedByPath = @{}
    foreach ($entry in $Expected) {
        $path = [string]$entry.path
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $expectedByPath[$path] = $entry
        }
    }

    $actualByPath = @{}
    foreach ($entry in $Actual) {
        $path = [string]$entry.path
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $actualByPath[$path] = $entry
        }
    }

    foreach ($path in @($expectedByPath.Keys | Sort-Object)) {
        if (-not $actualByPath.ContainsKey($path)) {
            $mismatches += "$Label missing actual path: $path"
            continue
        }
        $expectedEntry = $expectedByPath[$path]
        $actualEntry = $actualByPath[$path]
        if ([string]$expectedEntry.uid -ne [string]$actualEntry.uid) {
            $mismatches += "$Label uid changed for ${path}: expected $($expectedEntry.uid), got $($actualEntry.uid)"
        }
        if ($CompareSidecarPath -and [string]$expectedEntry.sidecar_path -ne [string]$actualEntry.sidecar_path) {
            $mismatches += "$Label sidecar path changed for ${path}: expected $($expectedEntry.sidecar_path), got $($actualEntry.sidecar_path)"
        }
    }

    foreach ($path in @($actualByPath.Keys | Sort-Object)) {
        if (-not $expectedByPath.ContainsKey($path)) {
            $mismatches += "$Label new actual path not in baseline: $path"
        }
    }
    return $mismatches
}

function New-SceneResourceReferenceBaseline {
    param(
        [Parameter(Mandatory = $true)]
        [array]$SceneReports
    )

    $entries = @()
    foreach ($report in $SceneReports) {
        $scenePath = [string]$report.scene_path
        if ([string]::IsNullOrWhiteSpace($scenePath)) {
            continue
        }
        $assetPaths = @(
            @($report.asset_paths) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        $entries += [PSCustomObject]@{
            scenePath = $scenePath
            assetPaths = @($assetPaths)
            assetPathCount = $assetPaths.Length
            declared = [int]$report.declared
            instantiated = [int]$report.instantiated
            visualChildren = [int]$report.visual_children
            fallbackVisuals = [int]$report.fallback_visuals
        }
    }
    return @($entries | Sort-Object -Property scenePath)
}

function Compare-SceneResourceReferenceBaseline {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Expected,

        [Parameter(Mandatory = $true)]
        [array]$Actual
    )

    $addedScenes = @()
    $removedScenes = @()
    $changedScenes = @()
    $expectedByScene = @{}
    foreach ($entry in $Expected) {
        $scenePath = [string]$entry.scenePath
        if (-not [string]::IsNullOrWhiteSpace($scenePath)) {
            $expectedByScene[$scenePath] = $entry
        }
    }
    $actualByScene = @{}
    foreach ($entry in $Actual) {
        $scenePath = [string]$entry.scenePath
        if (-not [string]::IsNullOrWhiteSpace($scenePath)) {
            $actualByScene[$scenePath] = $entry
        }
    }

    foreach ($scenePath in @($expectedByScene.Keys | Sort-Object)) {
        if (-not $actualByScene.ContainsKey($scenePath)) {
            $removedScenes += $scenePath
            continue
        }
        $expectedAssets = @(@($expectedByScene[$scenePath].assetPaths) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $actualAssets = @(@($actualByScene[$scenePath].assetPaths) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $expectedSet = @{}
        foreach ($asset in $expectedAssets) {
            $expectedSet[$asset] = $true
        }
        $actualSet = @{}
        foreach ($asset in $actualAssets) {
            $actualSet[$asset] = $true
        }
        $addedAssets = @($actualAssets | Where-Object { -not $expectedSet.ContainsKey($_) })
        $removedAssets = @($expectedAssets | Where-Object { -not $actualSet.ContainsKey($_) })
        if ($addedAssets.Length -gt 0 -or $removedAssets.Length -gt 0) {
            $changedScenes += [PSCustomObject]@{
                scenePath = $scenePath
                addedAssets = @($addedAssets)
                removedAssets = @($removedAssets)
                expectedAssetCount = $expectedAssets.Length
                actualAssetCount = $actualAssets.Length
            }
        }
    }

    foreach ($scenePath in @($actualByScene.Keys | Sort-Object)) {
        if (-not $expectedByScene.ContainsKey($scenePath)) {
            $addedScenes += $scenePath
        }
    }

    $changedAssetCount = 0
    foreach ($entry in $changedScenes) {
        $changedAssetCount += @($entry.addedAssets).Length + @($entry.removedAssets).Length
    }
    return [PSCustomObject]@{
        status = if ($addedScenes.Length -eq 0 -and $removedScenes.Length -eq 0 -and $changedScenes.Length -eq 0) { "matched" } else { "changed" }
        addedSceneCount = $addedScenes.Length
        removedSceneCount = $removedScenes.Length
        changedSceneCount = $changedScenes.Length
        changedAssetCount = $changedAssetCount
        addedScenes = @($addedScenes)
        removedScenes = @($removedScenes)
        changedScenes = @($changedScenes)
    }
}

function Export-SceneAssetDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConsoleLog,

        [Parameter(Mandatory = $true)]
        [string]$RunRoot,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
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
    $baselinePath = Join-Path $RepoRoot "docs\baselines\scene_asset_uid_baseline.json"
    $referenceBaselinePath = Join-Path $RepoRoot "docs\baselines\scene_resource_reference_baseline.json"
    $baselineStatus = "missing"
    $baselineMismatches = @()
    if (Test-Path -LiteralPath $baselinePath) {
        $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json -Depth 100
        $gltfMismatches = Compare-UidBaselineEntries `
            -Label "gltf import uid" `
            -Expected @($baseline.gltfImportUidBaseline) `
            -Actual @($counts.gltf_import_uid_baseline)
        $sidecarMismatches = Compare-UidBaselineEntries `
            -Label "asset sidecar uid" `
            -Expected @($baseline.assetUidSidecarBaseline) `
            -Actual @($counts.asset_uid_sidecar_baseline) `
            -CompareSidecarPath
        $baselineMismatches = @(
            @($gltfMismatches + $sidecarMismatches) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        $baselineStatus = if ($baselineMismatches.Length -eq 0) { "matched" } else { "mismatched" }
    }
    $sceneReferenceBaseline = New-SceneResourceReferenceBaseline -SceneReports @($counts.all_map_visual_scene_reports)
    $sceneReferenceStatus = "missing"
    $sceneReferenceDiff = [PSCustomObject]@{
        status = "missing"
        addedSceneCount = 0
        removedSceneCount = 0
        changedSceneCount = 0
        changedAssetCount = 0
        addedScenes = @()
        removedScenes = @()
        changedScenes = @()
    }
    if (Test-Path -LiteralPath $referenceBaselinePath) {
        $referenceBaseline = Get-Content -LiteralPath $referenceBaselinePath -Raw | ConvertFrom-Json -Depth 100
        $sceneReferenceDiff = Compare-SceneResourceReferenceBaseline `
            -Expected @($referenceBaseline.sceneResourceReferences) `
            -Actual @($sceneReferenceBaseline)
        $sceneReferenceStatus = [string]$sceneReferenceDiff.status
    }

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
            sceneResourceReferenceBaselineCount = $sceneReferenceBaseline.Length
            sceneResourceReferenceBaselineStatus = $sceneReferenceStatus
            sceneResourceReferenceChangedSceneCount = $sceneReferenceDiff.changedSceneCount
            sceneResourceReferenceChangedAssetCount = $sceneReferenceDiff.changedAssetCount
        }
        mapVisualSceneReports = @($counts.all_map_visual_scene_reports)
        mapVisualAssetPaths = @($counts.all_map_visual_asset_paths)
        sceneResourceReferenceBaseline = @($sceneReferenceBaseline)
        sceneResourceReferenceDiff = [ordered]@{
            baselinePath = $referenceBaselinePath
            status = $sceneReferenceStatus
            addedSceneCount = $sceneReferenceDiff.addedSceneCount
            removedSceneCount = $sceneReferenceDiff.removedSceneCount
            changedSceneCount = $sceneReferenceDiff.changedSceneCount
            changedAssetCount = $sceneReferenceDiff.changedAssetCount
            addedScenes = @($sceneReferenceDiff.addedScenes)
            removedScenes = @($sceneReferenceDiff.removedScenes)
            changedScenes = @($sceneReferenceDiff.changedScenes)
        }
        gltfAssetDiagnostics = @($counts.gltf_asset_diagnostics)
        gltfImportUidBaseline = @($counts.gltf_import_uid_baseline)
        assetUidSidecarBaseline = @($counts.asset_uid_sidecar_baseline)
        uidBaselineComparison = [ordered]@{
            baselinePath = $baselinePath
            status = $baselineStatus
            mismatchCount = $baselineMismatches.Length
            mismatches = @($baselineMismatches)
        }
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
    return [PSCustomObject]@{
        path = $diagnosticsPath
        baselinePath = $baselinePath
        baselineStatus = $baselineStatus
        baselineMismatchCount = $baselineMismatches.Length
        baselineMismatches = @($baselineMismatches)
    }
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
        $assetDiagnostics = $null
        $assetBaselinePath = $null
        $assetBaselineStatus = $null
        $assetBaselineMismatchCount = $null
        $sceneReferenceBaselineStatus = $null
        $sceneReferenceChangedSceneCount = $null
        $sceneReferenceChangedAssetCount = $null
        if ($name -eq "Scene" -and $exitCode -eq 0) {
            $assetDiagnosticResult = Export-SceneAssetDiagnostics -ConsoleLog $consoleLog -RunRoot $runRoot -RepoRoot $repoRoot
            $assetDiagnostics = $assetDiagnosticResult.path
            $assetBaselinePath = $assetDiagnosticResult.baselinePath
            $assetBaselineStatus = $assetDiagnosticResult.baselineStatus
            $assetBaselineMismatchCount = $assetDiagnosticResult.baselineMismatchCount
            $diagnosticJson = $null
            if ($assetDiagnostics -and (Test-Path -LiteralPath $assetDiagnostics)) {
                $diagnosticJson = Get-Content -LiteralPath $assetDiagnostics -Raw | ConvertFrom-Json -Depth 100
                $sceneReferenceBaselineStatus = [string]$diagnosticJson.sceneResourceReferenceDiff.status
                $sceneReferenceChangedSceneCount = [int]$diagnosticJson.sceneResourceReferenceDiff.changedSceneCount
                $sceneReferenceChangedAssetCount = [int]$diagnosticJson.sceneResourceReferenceDiff.changedAssetCount
            }
            if ($assetDiagnostics) {
                Write-Host "Scene asset diagnostics written to $assetDiagnostics"
            }
            if ($assetBaselineStatus -eq "mismatched") {
                Write-Host "Scene asset UID baseline mismatch against $assetBaselinePath"
                foreach ($mismatch in $assetDiagnosticResult.baselineMismatches) {
                    Write-Host "  $mismatch"
                }
                $exitCode = 1
            } elseif ($assetBaselineStatus -eq "matched") {
                Write-Host "Scene asset UID baseline matched $assetBaselinePath"
            } else {
                Write-Host "Scene asset UID baseline not found at $assetBaselinePath"
            }
        }
        $scenarioStatus = if ($exitCode -eq 0) { "passed" } else { "failed" }
        if ($exitCode -ne 0) {
            $status = "failed"
        }
        $results += [PSCustomObject]@{
            scenario = $name
            script = $scriptPath
            status = $scenarioStatus
            exitCode = $exitCode
            consoleLog = $consoleLog
            assetDiagnostics = $assetDiagnostics
            assetUidBaseline = $assetBaselinePath
            assetUidBaselineStatus = $assetBaselineStatus
            assetUidBaselineMismatchCount = $assetBaselineMismatchCount
            sceneResourceReferenceBaselineStatus = $sceneReferenceBaselineStatus
            sceneResourceReferenceChangedSceneCount = $sceneReferenceChangedSceneCount
            sceneResourceReferenceChangedAssetCount = $sceneReferenceChangedAssetCount
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
