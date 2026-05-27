<#
.SYNOPSIS
Open or reuse the Godot editor and select a specific content record.

.DESCRIPTION
This script is the Godot migration handoff entry for editor review and manual refinement.
It writes a navigation request to `tmp/editor_handoff/godot_editor.navigation.json`.
If a recent Godot editor session exists, the CDC Agent Handoff dock will pick up the request.
If no recent session exists, the script starts `D:\godot\godot.cmd --editor --path godot`.

.PARAMETER Item
Numeric item id to open in the Godot editor handoff dock.

.PARAMETER Recipe
Recipe id to open in the Godot editor handoff dock.

.PARAMETER Dialogue
Dialogue id to open in the Godot editor handoff dock.

.PARAMETER Quest
Quest id to open in the Godot editor handoff dock.

.PARAMETER Map
Map id to open in the Godot editor handoff dock.

.PARAMETER Character
Character id to open in the Godot editor handoff dock.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Item 1001

.EXAMPLE
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map survivor_outpost_01

.EXAMPLE
pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Quest tutorial_survive

.NOTES
Use exactly one of `-Item`, `-Recipe`, `-Dialogue`, `-Quest`, `-Map`, or `-Character`.
#>
[CmdletBinding()]
param(
    [int]$Item,
    [string]$Recipe,
    [string]$Dialogue,
    [string]$Quest,
    [string]$Map,
    [string]$Character,
    [string]$Godot = "D:\godot\godot.cmd"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-UnixTimeMilliseconds {
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function Test-RecentGodotEditorSession {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [int64]$MaxAgeMs = 30000
    )

    $sessionPath = Join-Path $RepoRoot "tmp/editor_handoff/godot_editor.session.json"
    if (-not (Test-Path -LiteralPath $sessionPath)) {
        return $null
    }

    try {
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }

    if ($session.state -ne "active") {
        return $null
    }

    $updatedAt = 0
    if ($null -ne $session.updated_at_unix_ms) {
        $updatedAt = [int64]$session.updated_at_unix_ms
    }
    if (((Get-UnixTimeMilliseconds) - $updatedAt) -gt $MaxAgeMs) {
        return $null
    }

    return $session
}

function Write-GodotNavigationRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$TargetKind,
        [Parameter(Mandatory = $true)]
        [string]$TargetId
    )

    $handoffDir = Join-Path $RepoRoot "tmp/editor_handoff"
    $requestPath = Join-Path $handoffDir "godot_editor.navigation.json"
    $timestampMs = Get-UnixTimeMilliseconds
    $request = [ordered]@{
        request_id = "godot_editor-$TargetKind-$timestampMs"
        target_editor = "godot_editor"
        action = "select_record"
        target_kind = $TargetKind
        target_id = $TargetId
        requested_at_unix_ms = $timestampMs
    }

    New-Item -ItemType Directory -Path $handoffDir -Force | Out-Null
    $request | ConvertTo-Json | Set-Content -LiteralPath $requestPath -NoNewline
}

function Try-FocusEditorProcess {
    param(
        [Parameter(Mandatory = $true)]
        [uint32]$TargetProcessId
    )

    try {
        $wshell = New-Object -ComObject WScript.Shell
        return $wshell.AppActivate($TargetProcessId)
    }
    catch {
        return $false
    }
}

$requestedTargets = @(
    if ($PSBoundParameters.ContainsKey("Item")) { "item" }
    if ($PSBoundParameters.ContainsKey("Recipe")) { "recipe" }
    if ($PSBoundParameters.ContainsKey("Dialogue")) { "dialogue" }
    if ($PSBoundParameters.ContainsKey("Quest")) { "quest" }
    if ($PSBoundParameters.ContainsKey("Map")) { "map" }
    if ($PSBoundParameters.ContainsKey("Character")) { "character" }
)

if ($requestedTargets.Count -ne 1) {
    throw "use exactly one of -Item, -Recipe, -Dialogue, -Quest, -Map, or -Character"
}
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot command not found: $Godot"
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$godotProject = Join-Path $repoRoot "godot"
if (-not (Test-Path -LiteralPath $godotProject)) {
    throw "Godot project not found: $godotProject"
}

$targetKind = $requestedTargets[0]
$targetId = switch ($targetKind) {
    "item" { "$Item" }
    "recipe" { $Recipe }
    "dialogue" { $Dialogue }
    "quest" { $Quest }
    "map" { $Map }
    "character" { $Character }
    default { throw "unsupported navigation target: $targetKind" }
}
if ([string]::IsNullOrWhiteSpace($targetId)) {
    throw "-$targetKind requires a non-empty id"
}

Write-GodotNavigationRequest -RepoRoot $repoRoot -TargetKind $targetKind -TargetId $targetId

$existingSession = Test-RecentGodotEditorSession -RepoRoot $repoRoot
if ($null -ne $existingSession) {
    $focused = $false
    if ($null -ne $existingSession.pid) {
        $focused = Try-FocusEditorProcess -TargetProcessId ([uint32]$existingSession.pid)
    }
    if ($focused) {
        Write-Host "Updated existing Godot editor selection and focused PID $($existingSession.pid)."
    }
    else {
        Write-Host "Updated existing Godot editor selection for PID $($existingSession.pid)."
    }
    exit 0
}

$process = Start-Process -FilePath $Godot -ArgumentList @("--editor", "--path", "godot") -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru
Write-Host "Started Godot editor process $($process.Id) and wrote navigation request for $targetKind $targetId."
