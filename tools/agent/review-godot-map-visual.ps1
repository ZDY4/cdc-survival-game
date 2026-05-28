<#
.SYNOPSIS
Run the Godot map visual review flow for a map id.

.DESCRIPTION
This script is the repo-local Godot entrypoint for map review.
It runs the Godot content CLI locate, summarize, references, and validate commands,
then optionally runs the target map preview smoke plus global world and scene
runtime smoke scenarios.

.PARAMETER Map
Map id to review.

.PARAMETER NoSmoke
When set, only print content review information and skip Godot world/scene smoke checks.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01

.EXAMPLE
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01 -NoSmoke

.NOTES
The interactive Godot preview/editor surface lives in the `CDC Map Preview` dock.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Map,

    [switch]$NoSmoke,

    [string]$Godot = "D:\godot\godot.cmd"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "=== $Title ==="
    & $Action 2>&1 | Out-Host
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
        $exitCode = 0
    }
    if ($exitCode -ne 0) {
        throw "$Title failed with exit code $exitCode"
    }
}

if ([string]::IsNullOrWhiteSpace($Map)) {
    throw "-Map requires a non-empty map id"
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$godotContentScript = Join-Path $repoRoot "tools/agent/godot-content.ps1"
$godotSmokeScript = Join-Path $repoRoot "tools/agent/test-godot-game.ps1"

if (-not (Test-Path -LiteralPath $godotContentScript)) {
    throw "Godot content wrapper not found: $godotContentScript"
}
if (-not $NoSmoke -and -not (Test-Path -LiteralPath $godotSmokeScript)) {
    throw "Godot smoke wrapper not found: $godotSmokeScript"
}

Push-Location $repoRoot
try {
    Invoke-Step -Title "Locate map file with Godot content CLI" -Action {
        pwsh -NoProfile -File $godotContentScript -Command locate -Kind map -Id $Map -Godot $Godot
    }

    Invoke-Step -Title "Summarize map with Godot content CLI" -Action {
        pwsh -NoProfile -File $godotContentScript -Command summarize -Kind map -Id $Map -Godot $Godot
    }

    Invoke-Step -Title "Check overworld references with Godot content CLI" -Action {
        pwsh -NoProfile -File $godotContentScript -Command references -Kind map -Id $Map -Godot $Godot
    }

    Invoke-Step -Title "Validate migrated content with Godot loader" -Action {
        pwsh -NoProfile -File $godotContentScript -Command validate -Kind changed -Godot $Godot
    }

    if (-not $NoSmoke) {
        Invoke-Step -Title "Run Godot map preview smoke" -Action {
            & $Godot --headless --path godot --script "res://scripts/tools/map_preview_smoke.gd" -- map $Map
        }

        Invoke-Step -Title "Run Godot world snapshot smoke" -Action {
            pwsh -NoProfile -File $godotSmokeScript -Scenario World -Godot $Godot
        }

        Invoke-Step -Title "Run Godot generated scene smoke" -Action {
            pwsh -NoProfile -File $godotSmokeScript -Scenario Scene -Godot $Godot
        }
    }

    Write-Host ""
    Write-Host "=== Godot Map Review Checklist ==="
    Write-Host "1. Confirm the content CLI located the intended map file."
    Write-Host "2. Check size, default level, entry points, object count, and object kind summary."
    Write-Host "3. Check overworld references, entry_point_id, and location kind for this map."
    if ($NoSmoke) {
        Write-Host "4. Godot map preview/world/scene smoke was skipped by -NoSmoke; run without it before accepting spatial changes."
    } else {
        Write-Host "4. Confirm Godot loader validation and target map preview smoke passed."
    }
    Write-Host "5. Treat World and Scene smoke as global runtime regressions; they currently boot the default scenario."
    Write-Host "6. If layout changed, inspect the CDC Map Preview dock and compare the generated scene result with the intended JSON edits."
    Write-Host ""
    Write-Host "Godot editor handoff note: use open-godot-editor.ps1 -Map $Map to inspect the handoff summary and the CDC Map Preview dock."
}
finally {
    Pop-Location
}
