<#
.SYNOPSIS
Run the standard map visual review flow for a map id.

.DESCRIPTION
This script is the standard repo-local visual review entry for map changes.
It runs `content_tools` locate, summarize, references, and validate commands inside the Rust
workspace, prints a fixed review checklist, and then optionally opens or reuses `bevy_map_editor`
through `tools/agent/open-editor.ps1`.

.PARAMETER Map
Map id to review.

.PARAMETER NoOpenEditor
When set, only print CLI review information and skip opening `bevy_map_editor`.

.EXAMPLE
pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map forest

.EXAMPLE
pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map factory -NoOpenEditor

.NOTES
This workflow is intended for post-edit spatial review, not for editing map data directly inside
the script.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Map,
    [switch]$NoOpenEditor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [int[]]$AllowedExitCodes = @(0),
        [ref]$ExitCodeRef = ([ref]0)
    )

    Write-Host ""
    Write-Host "=== $Title ==="
    & $Action 2>&1 | Out-Host
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
        $exitCode = 0
    }
    $ExitCodeRef.Value = $exitCode
    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "$Title failed with exit code $exitCode"
    }
}

if ([string]::IsNullOrWhiteSpace($Map)) {
    throw "-Map requires a non-empty map id"
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$rustWorkspaceRoot = Join-Path $repoRoot "rust"
$contentToolsArgs = @("run", "-q", "-p", "content_tools", "--")

Push-Location $rustWorkspaceRoot
try {
    $stepExitCode = 0

    Invoke-Step -Title "Locate map file" -Action {
        cargo @contentToolsArgs locate map $Map
    } -ExitCodeRef ([ref]$stepExitCode)

    Invoke-Step -Title "Summarize map" -Action {
        cargo @contentToolsArgs summarize map $Map
    } -ExitCodeRef ([ref]$stepExitCode)

    Invoke-Step -Title "Check overworld references" -Action {
        cargo @contentToolsArgs references map $Map
    } -ExitCodeRef ([ref]$stepExitCode)

    $validationExitCode = 0
    Invoke-Step -Title "Validate map" -AllowedExitCodes @(0, 2) -Action {
        cargo @contentToolsArgs validate map $Map
    } -ExitCodeRef ([ref]$validationExitCode)

    Write-Host ""
    Write-Host "=== Visual Review Checklist ==="
    Write-Host "1. Confirm the correct map and active level are selected."
    Write-Host "2. Check entry points, spawn positions, and key interactable objects."
    Write-Host "3. Inspect scene diagnostics, blocked paths, and obvious traversal issues."
    Write-Host "4. Compare the rendered result with the intended JSON changes before concluding."
    if ($validationExitCode -eq 2) {
        Write-Warning "Map validation reported diagnostics. Review the editor state carefully before accepting the change."
    }

    if (-not $NoOpenEditor) {
        Invoke-Step -Title "Open map editor for visual review" -Action {
            pwsh -NoProfile -File (Join-Path $repoRoot "tools/agent/open-editor.ps1") -Map $Map
        } -ExitCodeRef ([ref]$stepExitCode)
    }
}
finally {
    Pop-Location
}
