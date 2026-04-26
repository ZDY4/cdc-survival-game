param(
    [string[]]$Editors = @(
        "bevy_item_editor",
        "bevy_recipe_editor",
        "bevy_dialogue_editor",
        "bevy_quest_editor",
        "bevy_character_editor",
        "bevy_map_editor"
    ),
    [int]$StartupTimeoutSec = 240,
    [int]$AliveCheckSec = 5,
    [string]$OutputRoot,
    [switch]$KeepOpen,
    [switch]$SkipScreenshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\smoke"
}

$editorConfigs = @{
    bevy_item_editor = @{
        AppId = "bevy_item_editor"
        Title = "CDC Item Editor"
        Launcher = Join-Path $repoRoot "run_bevy_item_editor.bat"
    }
    bevy_recipe_editor = @{
        AppId = "bevy_recipe_editor"
        Title = "CDC Recipe Editor"
        Launcher = Join-Path $repoRoot "run_bevy_recipe_editor.bat"
    }
    bevy_dialogue_editor = @{
        AppId = "bevy_dialogue_editor"
        Title = "CDC Dialogue Viewer"
        Launcher = Join-Path $repoRoot "run_bevy_dialogue_editor.bat"
    }
    bevy_quest_editor = @{
        AppId = "bevy_quest_editor"
        Title = "CDC Quest Viewer"
        Launcher = Join-Path $repoRoot "run_bevy_quest_editor.bat"
    }
    bevy_character_editor = @{
        AppId = "bevy_character_editor"
        Title = "CDC Character Editor"
        Launcher = Join-Path $repoRoot "run_bevy_character_editor.bat"
    }
    bevy_map_editor = @{
        AppId = "bevy_map_editor"
        Title = "CDC Map Editor"
        Launcher = Join-Path $repoRoot "run_bevy_map_editor.bat"
    }
}

$unknownEditors = @($Editors | Where-Object { -not $editorConfigs.ContainsKey($_) })
if ($unknownEditors.Count -gt 0) {
    throw "unknown editor ids: $($unknownEditors -join ', ')"
}

$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class SmokeWindowNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

Add-Type -AssemblyName System.Drawing

function Get-ProcessGraph {
    $graph = @{}
    foreach ($process in Get-CimInstance Win32_Process) {
        $parentId = [int]$process.ParentProcessId
        if (-not $graph.ContainsKey($parentId)) {
            $graph[$parentId] = [System.Collections.Generic.List[int]]::new()
        }
        $graph[$parentId].Add([int]$process.ProcessId)
    }
    return $graph
}

function Get-DescendantProcessIds {
    param(
        [int]$RootId
    )

    $graph = Get-ProcessGraph
    $seen = [System.Collections.Generic.HashSet[int]]::new()
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($RootId)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $graph.ContainsKey($current)) {
            continue
        }
        foreach ($childId in $graph[$current]) {
            if ($seen.Add($childId)) {
                $queue.Enqueue($childId)
            }
        }
    }

    return @($seen)
}

function Get-TrackedProcesses {
    param(
        [int]$RootId
    )

    $ids = @($RootId) + (Get-DescendantProcessIds -RootId $RootId)
    $ids = @($ids | Sort-Object -Unique)
    if ($ids.Count -eq 0) {
        return @()
    }
    return @(Get-Process -Id $ids -ErrorAction SilentlyContinue)
}

function Find-EditorWindowProcess {
    param(
        [int]$RootId,
        [string]$ExpectedTitle
    )

    $tracked = Get-TrackedProcesses -RootId $RootId
    $windowed = @(
        $tracked |
            Where-Object { $_.MainWindowHandle -ne 0 } |
            Sort-Object StartTime
    )
    if ($windowed.Count -eq 0) {
        return $null
    }

    $matching = @(
        $windowed |
            Where-Object { $_.MainWindowTitle -like "*$ExpectedTitle*" }
    )
    if ($matching.Count -gt 0) {
        return $matching[-1]
    }

    return $windowed[-1]
}

function Stop-ProcessTree {
    param(
        [int]$RootId
    )

    $ids = @($RootId) + (Get-DescendantProcessIds -RootId $RootId)
    foreach ($id in @($ids | Sort-Object -Descending -Unique)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

function Save-WindowScreenshot {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$OutputPath
    )

    if ($Process.MainWindowHandle -eq 0) {
        throw "process $($Process.Id) has no main window"
    }

    [SmokeWindowNative]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 250

    $rect = New-Object SmokeWindowNative+RECT
    if (-not [SmokeWindowNative]::GetWindowRect($Process.MainWindowHandle, [ref]$rect)) {
        throw "failed to get window rect for process $($Process.Id)"
    }

    $width = [Math]::Max(1, $rect.Right - $rect.Left)
    $height = [Math]::Max(1, $rect.Bottom - $rect.Top)

    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen(
            $rect.Left,
            $rect.Top,
            0,
            0,
            [System.Drawing.Size]::new($width, $height)
        )
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-NewLogFile {
    param(
        [string]$AppId,
        [string[]]$ExistingLogPaths,
        [datetime]$StartedAt
    )

    $logDir = Join-Path $repoRoot "logs\$AppId"
    if (-not (Test-Path -LiteralPath $logDir)) {
        return $null
    }

    $newLogs = @(
        Get-ChildItem -Path $logDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notin $ExistingLogPaths -and $_.LastWriteTime -ge $StartedAt.AddSeconds(-2)
            } |
            Sort-Object LastWriteTime -Descending
    )

    if ($newLogs.Count -gt 0) {
        return $newLogs[0]
    }

    return $null
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($editorId in $Editors) {
    $config = $editorConfigs[$editorId]
    $appRoot = Join-Path $runRoot $editorId
    New-Item -ItemType Directory -Path $appRoot -Force | Out-Null

    $consoleLog = Join-Path $appRoot "console.log"
    $screenshotPath = Join-Path $appRoot "window.png"
    $launcherWrapper = Join-Path $appRoot "launch-wrapper.cmd"
    $existingLogs = @()
    $logDir = Join-Path $repoRoot "logs\$($config.AppId)"
    if (Test-Path -LiteralPath $logDir) {
        $existingLogs = @(Get-ChildItem -Path $logDir -Filter "*.log" -File | Select-Object -ExpandProperty FullName)
    }

    @(
        "@echo off"
        "call `"$($config.Launcher)`" > `"$consoleLog`" 2>&1"
        "exit /b %ERRORLEVEL%"
    ) | Set-Content -Path $launcherWrapper

    $startedAt = Get-Date
    $rootProcess = Start-Process -FilePath "cmd.exe" `
        -ArgumentList @("/d", "/s", "/c", "`"$launcherWrapper`"") `
        -PassThru `
        -WindowStyle Hidden

    $windowProcess = $null
    $deadline = $startedAt.AddSeconds($StartupTimeoutSec)
    $failureReason = $null

    while ((Get-Date) -lt $deadline) {
        $windowProcess = Find-EditorWindowProcess -RootId $rootProcess.Id -ExpectedTitle $config.Title
        if ($null -ne $windowProcess) {
            break
        }

        if ($rootProcess.HasExited) {
            $failureReason = "launcher exited before editor window appeared (exit code: $($rootProcess.ExitCode))"
            break
        }

        Start-Sleep -Milliseconds 500
    }

    if ($null -eq $windowProcess -and $null -eq $failureReason) {
        $failureReason = "timed out waiting for editor window"
    }

    $latestLog = $null
    $status = "passed"
    $errorMessage = $null

    try {
        if ($null -ne $failureReason) {
            throw $failureReason
        }

        Start-Sleep -Seconds $AliveCheckSec
        $windowProcess.Refresh()
        if ($windowProcess.HasExited) {
            throw "editor window process exited during alive check"
        }

        $latestLog = Get-NewLogFile -AppId $config.AppId -ExistingLogPaths $existingLogs -StartedAt $startedAt
        if ($null -eq $latestLog) {
            throw "new runtime log was not created under logs/$($config.AppId)"
        }

        if (-not $SkipScreenshot) {
            Save-WindowScreenshot -Process $windowProcess -OutputPath $screenshotPath
        }
    }
    catch {
        $status = "failed"
        $errorMessage = $_.Exception.Message
    }
    finally {
        if (-not $KeepOpen) {
            Stop-ProcessTree -RootId $rootProcess.Id
        }
    }

    $result = [PSCustomObject]@{
        editor = $editorId
        status = $status
        launcher = $config.Launcher
        startedAt = $startedAt.ToString("o")
        launcherRootPid = $rootProcess.Id
        windowProcessId = if ($null -ne $windowProcess) { $windowProcess.Id } else { $null }
        windowTitle = if ($null -ne $windowProcess) { $windowProcess.MainWindowTitle } else { $null }
        runtimeLog = if ($null -ne $latestLog) { $latestLog.FullName } else { $null }
        consoleLog = $consoleLog
        launcherWrapper = $launcherWrapper
        screenshot = if ((-not $SkipScreenshot) -and (Test-Path -LiteralPath $screenshotPath)) { $screenshotPath } else { $null }
        error = $errorMessage
    }
    $results.Add($result)

    $result |
        ConvertTo-Json -Depth 4 |
        Set-Content -Path (Join-Path $appRoot "result.json")
}

$summaryPath = Join-Path $runRoot "summary.json"
$results |
    ConvertTo-Json -Depth 4 |
    Set-Content -Path $summaryPath

$failed = @($results | Where-Object { $_.status -ne "passed" })
if ($failed.Count -gt 0) {
    Write-Error "bevy editor smoke failed; see $summaryPath"
}

Write-Host "Smoke results written to $summaryPath"
