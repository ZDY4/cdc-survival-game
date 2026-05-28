<#
.SYNOPSIS
Runs deterministic Godot editor smoke scenarios.

.DESCRIPTION
This script is the repo-local agent entrypoint for Godot editor migration smoke checks.
It runs Godot 4.6.3 headless scripts that cover the CDC Agent Handoff dock, CDC Content
Browser dock, CDC Map Preview dock, and the shared content edit services used by those
editor surfaces.

.PARAMETER Scenario
Editor smoke scenario to run. Use `All` to run every Godot editor smoke scenario.

.PARAMETER OutputRoot
Directory for console logs and JSON result output. Defaults to `.local/agent-smoke/godot_editor`.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario MapPreview

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-editor.ps1 -Scenario All
#>
[CmdletBinding()]
param(
    [ValidateSet(
        "All",
        "EditorHandoff",
        "ContentBrowser",
        "MapPreview",
        "ContentEdit",
        "MapEdit"
    )]
    [string]$Scenario = "All",

    [string]$OutputRoot,

    [string]$Godot = "D:\godot\godot.cmd"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\agent-smoke\godot_editor"
}
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot command not found: $Godot"
}

$scenarioScripts = [ordered]@{
    EditorHandoff = "res://scripts/tools/editor_handoff_smoke.gd"
    ContentBrowser = "res://scripts/tools/editor_content_browser_smoke.gd"
    MapPreview = "res://scripts/tools/map_preview_smoke.gd"
    ContentEdit = "res://scripts/tools/content_edit_service_smoke.gd"
    MapEdit = "res://scripts/tools/map_edit_service_smoke.gd"
}

$selected = @()
if ($Scenario -eq "All") {
    $selected = @($scenarioScripts.Keys)
} else {
    $selected = @($Scenario)
}

$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$startedAt = Get-Date
$status = "passed"
$results = @()

Push-Location $repoRoot
try {
    foreach ($name in $selected) {
        $scriptPath = $scenarioScripts[$name]
        $consoleLog = Join-Path $runRoot ("{0}.log" -f $name)
        Write-Host "Running Godot editor smoke scenario '$name' with script '$scriptPath'"
        & $Godot --headless --path godot --script $scriptPath 2>&1 |
            Tee-Object -FilePath $consoleLog
        $exitCode = $LASTEXITCODE
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
    Write-Error "Godot editor smoke failed; see $resultPath"
}

Write-Host "Godot editor smoke result written to $resultPath"
