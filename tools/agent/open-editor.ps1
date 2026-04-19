param(
    [int]$Item,
    [string]$Recipe,
    [string]$Map,
    [string]$Character
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-UnixTimeMilliseconds {
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function Get-EditorFileStem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    switch ($Target) {
        "item" { return "bevy_item_editor" }
        "recipe" { return "bevy_recipe_editor" }
        "map" { return "bevy_map_editor" }
        "character" { return "bevy_character_editor" }
        default { throw "unsupported editor target: $Target" }
    }
}

function Test-RecentEditorSession {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [int64]$MaxAgeMs = 30000
    )

    $fileStem = Get-EditorFileStem -Target $Target
    $sessionPath = Join-Path $RepoRoot "tmp/editor_handoff/$fileStem.session.json"
    if (-not (Test-Path -LiteralPath $sessionPath)) {
        return $null
    }

    try {
        $session = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
    }
    catch {
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

function Write-EditorNavigationRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $true)]
        [string]$TargetKind,
        [Parameter(Mandatory = $true)]
        [string]$TargetId
    )

    $fileStem = Get-EditorFileStem -Target $Target
    $handoffDir = Join-Path $RepoRoot "tmp/editor_handoff"
    $requestPath = Join-Path $handoffDir "$fileStem.navigation.json"
    $timestampMs = Get-UnixTimeMilliseconds
    $request = [ordered]@{
        request_id = "$fileStem-$TargetKind-$timestampMs"
        target_editor = $Target
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
    if ($PSBoundParameters.ContainsKey("Map")) { "map" }
    if ($PSBoundParameters.ContainsKey("Character")) { "character" }
)

if ($requestedTargets.Count -ne 1) {
    throw "use exactly one of -Item, -Recipe, -Map, or -Character"
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))

switch ($requestedTargets[0]) {
    "item" {
        $launcher = Join-Path $repoRoot "run_bevy_item_editor.bat"
        $arguments = @("--select-item", "$Item")
    }
    "recipe" {
        if ([string]::IsNullOrWhiteSpace($Recipe)) {
            throw "-Recipe requires a non-empty recipe id"
        }
        $launcher = Join-Path $repoRoot "run_bevy_recipe_editor.bat"
        $arguments = @("--select-recipe", $Recipe)
    }
    "map" {
        if ([string]::IsNullOrWhiteSpace($Map)) {
            throw "-Map requires a non-empty map id"
        }
        $launcher = Join-Path $repoRoot "run_bevy_map_editor.bat"
        $arguments = @("--select-map", $Map)
    }
    "character" {
        if ([string]::IsNullOrWhiteSpace($Character)) {
            throw "-Character requires a non-empty character id"
        }
        $launcher = Join-Path $repoRoot "run_bevy_character_editor.bat"
        $arguments = @("--select-character", $Character)
    }
}

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "launcher not found: $launcher"
}

$existingSession = $null
if ($requestedTargets[0] -in @("item", "recipe", "map", "character")) {
    $existingSession = Test-RecentEditorSession -RepoRoot $repoRoot -Target $requestedTargets[0]
}

if ($null -ne $existingSession) {
    $targetId = switch ($requestedTargets[0]) {
        "item" { "$Item" }
        "recipe" { $Recipe }
        "map" { $Map }
        "character" { $Character }
        default { throw "unsupported navigation target: $($requestedTargets[0])" }
    }
    Write-EditorNavigationRequest -RepoRoot $repoRoot -Target $requestedTargets[0] -TargetKind $requestedTargets[0] -TargetId $targetId
    $focused = $false
    if ($null -ne $existingSession.pid) {
        $focused = Try-FocusEditorProcess -TargetProcessId ([uint32]$existingSession.pid)
    }
    if ($focused) {
        Write-Host "Updated existing $($requestedTargets[0]) editor selection and focused PID $($existingSession.pid)."
    }
    else {
        Write-Host "Updated existing $($requestedTargets[0]) editor selection for PID $($existingSession.pid)."
    }
    exit 0
}

$process = Start-Process -FilePath $launcher -ArgumentList $arguments -WorkingDirectory $repoRoot -PassThru
Write-Host "Started editor process $($process.Id) via $launcher"
