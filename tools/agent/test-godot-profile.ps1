<#
.SYNOPSIS
Runs Godot runtime profiling scenarios.

.DESCRIPTION
This script is the repo-local agent entrypoint for repeatable Godot runtime
profiling. It runs `godot/scripts/tools/runtime_profile_probe.gd`, captures the
Godot console log, and writes machine-readable profiling JSON under
`.local/agent-smoke/godot_profile`.

.PARAMETER Scenario
Profiling scenario to run. Currently supports `MovementClickRepeat`.

.PARAMETER Map
Map id expected by the scenario. The current startup runtime defaults to
`survivor_outpost_01`.

.PARAMETER Iterations
Number of scenario repetitions.

.PARAMETER MaxFramesPerMove
Maximum frames to wait for each movement command.

.PARAMETER OutputRoot
Directory for console logs and JSON result output. Defaults to
`.local/agent-smoke/godot_profile`.

.PARAMETER Godot
Path to the Godot command line entrypoint. If omitted, resolves from the `GODOT` environment variable,
then PATH, then `D:\godot\godot.cmd`.

.PARAMETER Headless
Run Godot in headless mode. Visible mode is the default so input, camera,
physics picking, and frame pacing match the interactive runtime more closely.

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-profile.ps1

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-profile.ps1 -Scenario MovementClickRepeat -Iterations 30

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-profile.ps1 -Scenario MovementClickRepeat -Map survivor_outpost_01 -Iterations 20 -Headless
#>
[CmdletBinding()]
param(
    [ValidateSet("MovementClickRepeat")]
    [string]$Scenario = "MovementClickRepeat",

    [string]$Map = "survivor_outpost_01",

    [ValidateRange(1, 10000)]
    [int]$Iterations = 20,

    [ValidateRange(1, 100000)]
    [int]$MaxFramesPerMove = 720,

    [string]$OutputRoot,

    [string]$Godot,

    [switch]$Headless
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "godot-env.ps1")

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\agent-smoke\godot_profile"
}
$Godot = Resolve-AgentGodotCommand -Godot $Godot

$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$consoleLog = Join-Path $runRoot ("{0}.log" -f $Scenario)
$profilePath = Join-Path $runRoot ("{0}.profile.json" -f $Scenario)
$resultPath = Join-Path $runRoot "result.json"

$godotArgs = @(
    "--path", "godot",
    "--script", "res://scripts/tools/runtime_profile_probe.gd",
    "--disable-vsync",
    "--max-fps", "0",
    "--",
    "--scenario=$Scenario",
    "--map=$Map",
    "--iterations=$Iterations",
    "--max-frames-per-move=$MaxFramesPerMove",
    "--output=$(([System.IO.Path]::GetFullPath($profilePath)).Replace('\', '/'))"
)
if ($Headless) {
    $godotArgs = @("--headless") + $godotArgs
}

$startedAt = Get-Date
$status = "passed"

Push-Location $repoRoot
try {
    Write-Host "Running Godot profile scenario '$Scenario' on map '$Map' for $Iterations iterations"
    & $Godot @godotArgs 2>&1 | Tee-Object -FilePath $consoleLog
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $status = "failed"
    }
}
finally {
    Pop-Location
}

$profile = $null
$summary = $null
$functionSummary = $null
if (Test-Path -LiteralPath $profilePath) {
    $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json -Depth 100
    $summary = $profile.summary
    $functionSummary = $profile.function_summary
} elseif ($status -eq "passed") {
    $status = "failed"
}

$result = [PSCustomObject]@{
    scenario = $Scenario
    map = $Map
    iterations = $Iterations
    status = $status
    startedAt = $startedAt.ToString("o")
    finishedAt = (Get-Date).ToString("o")
    consoleLog = $consoleLog
    profile = $profilePath
    summary = $summary
    functionSummary = $functionSummary
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resultPath

if ($summary -ne $null) {
    Write-Host "Godot profile summary:"
    $summary | ConvertTo-Json -Depth 20 | Write-Host
}
Write-Host "Godot profile result written to $resultPath"

if ($status -ne "passed") {
    Write-Error "Godot profile failed; see $resultPath"
}
