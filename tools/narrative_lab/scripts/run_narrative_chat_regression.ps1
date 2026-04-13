[CmdletBinding()]
param(
    [ValidateSet("offline", "online", "online-core", "online-structured")]
    [string]$Mode = "offline",
    [int]$TimeoutSec = 600,
    [int]$StableReportSec = 3,
    [switch]$Cleanup
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$editorDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent (Split-Path -Parent $editorDir)
$seedWorkspace = Join-Path $editorDir "test-fixtures\workspace_seed"
$runtimeRoot = Join-Path $repoRoot "tmp\narrative_lab_regression_$Mode"
$stubPort = 18765
$stubProcess = $null
$appProcess = $null
$stubLogPath = Join-Path $runtimeRoot "stub.log"
$appStdoutPath = Join-Path $runtimeRoot "app.stdout.log"
$appStderrPath = Join-Path $runtimeRoot "app.stderr.log"

function Stop-ProcessTree {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId
    )

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId $child.ProcessId
    }

    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
    } catch {
        # Ignore already-exited processes so cleanup stays best-effort.
    }
}

function Get-LatestRegressionReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $reportDir = Join-Path $WorkspaceRoot "exports\chat_regressions"
    if (-not (Test-Path $reportDir)) {
        return $null
    }

    Get-ChildItem -Path $reportDir -Filter "*.json" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Wait-ForStableRegressionReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSec,
        [Parameter(Mandatory = $true)]
        [int]$StableReportSec
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $stableFor = [Math]::Max($StableReportSec, 1)

    while ((Get-Date) -lt $deadline) {
        $report = Get-LatestRegressionReport -WorkspaceRoot $WorkspaceRoot
        if ($null -ne $report) {
            $initialStamp = $report.LastWriteTimeUtc
            Start-Sleep -Seconds $stableFor
            $latest = Get-LatestRegressionReport -WorkspaceRoot $WorkspaceRoot
            if (
                $null -ne $latest -and
                $latest.FullName -eq $report.FullName -and
                $latest.LastWriteTimeUtc -eq $initialStamp
            ) {
                return $latest
            }
            continue
        }

        if ($Process.HasExited) {
            break
        }

        Start-Sleep -Milliseconds 500
    }

    return $null
}

if (-not (Test-Path $seedWorkspace)) {
    throw "Regression workspace seed not found: $seedWorkspace"
}

if (Test-Path $runtimeRoot) {
    Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $runtimeRoot | Out-Null
Copy-Item -Path (Join-Path $seedWorkspace "*") -Destination $runtimeRoot -Recurse -Force

$previousEnv = @{
    CDC_EDITOR_SELF_TEST = $env:CDC_EDITOR_SELF_TEST
    CDC_EDITOR_SELF_TEST_AUTOCLOSE = $env:CDC_EDITOR_SELF_TEST_AUTOCLOSE
    CDC_NARRATIVE_CHAT_REGRESSION_MODE = $env:CDC_NARRATIVE_CHAT_REGRESSION_MODE
    CDC_NARRATIVE_WORKSPACE_ROOT = $env:CDC_NARRATIVE_WORKSPACE_ROOT
    CDC_NARRATIVE_PROJECT_ROOT = $env:CDC_NARRATIVE_PROJECT_ROOT
    CDC_NARRATIVE_AI_BASE_URL = $env:CDC_NARRATIVE_AI_BASE_URL
    CDC_NARRATIVE_AI_MODEL = $env:CDC_NARRATIVE_AI_MODEL
    CDC_NARRATIVE_AI_API_KEY = $env:CDC_NARRATIVE_AI_API_KEY
    CDC_NARRATIVE_AI_TIMEOUT_SEC = $env:CDC_NARRATIVE_AI_TIMEOUT_SEC
    CDC_NARRATIVE_STUB_LOG = $env:CDC_NARRATIVE_STUB_LOG
}

try {
    $env:CDC_EDITOR_SELF_TEST = "narrative-chat-regression"
    $env:CDC_EDITOR_SELF_TEST_AUTOCLOSE = "1"
    $env:CDC_NARRATIVE_CHAT_REGRESSION_MODE = $Mode
    $env:CDC_NARRATIVE_WORKSPACE_ROOT = $runtimeRoot
    $env:CDC_NARRATIVE_PROJECT_ROOT = $repoRoot

    if ($Mode -eq "offline") {
        $env:CDC_NARRATIVE_AI_BASE_URL = "http://127.0.0.1:$stubPort/v1"
        $env:CDC_NARRATIVE_AI_MODEL = "narrative-lab-stub"
        $env:CDC_NARRATIVE_AI_API_KEY = "stub-key"
        $env:CDC_NARRATIVE_AI_TIMEOUT_SEC = "12"
        $env:CDC_NARRATIVE_STUB_LOG = $stubLogPath

        $stubScript = Join-Path $scriptDir "narrative_ai_stub.mjs"
        $stubProcess = Start-Process -FilePath "node" -ArgumentList @($stubScript, "--port", "$stubPort") -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 1
    }

    Push-Location $repoRoot
    try {
        $appProcess = Start-Process -FilePath "cmd.exe" `
            -ArgumentList @("/c", (Join-Path $repoRoot "run_narrative_lab.bat"), "--self-test", "narrative-chat-regression") `
            -WorkingDirectory $repoRoot `
            -RedirectStandardOutput $appStdoutPath `
            -RedirectStandardError $appStderrPath `
            -PassThru

        $report = Wait-ForStableRegressionReport `
            -WorkspaceRoot $runtimeRoot `
            -Process $appProcess `
            -TimeoutSec $TimeoutSec `
            -StableReportSec $StableReportSec

        if ($null -eq $report) {
            if ($appProcess.HasExited) {
                throw "Narrative Lab exited before exporting a regression report. Exit code: $($appProcess.ExitCode). Stdout: $appStdoutPath Stderr: $appStderrPath"
            }
            throw "Timed out after $TimeoutSec seconds waiting for a regression report under $runtimeRoot\exports\chat_regressions. Stdout: $appStdoutPath Stderr: $appStderrPath"
        }
    } finally {
        Pop-Location
    }

    $payload = Get-Content -LiteralPath $report.FullName -Raw | ConvertFrom-Json
    Write-Host "Regression report:" $report.FullName
    Write-Host "Summary:" $payload.summary
    Write-Host "Mode:" $payload.mode
    Write-Host "Passed:" $payload.ok
    Write-Host "App stdout:" $appStdoutPath
    Write-Host "App stderr:" $appStderrPath
} finally {
    foreach ($entry in $previousEnv.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue
        } else {
            Set-Item "Env:$($entry.Key)" $entry.Value
        }
    }

    if ($null -ne $appProcess -and -not $appProcess.HasExited) {
        Stop-ProcessTree -ProcessId $appProcess.Id
    }

    if ($null -ne $stubProcess -and -not $stubProcess.HasExited) {
        Stop-ProcessTree -ProcessId $stubProcess.Id
    }

    if ($Cleanup) {
        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
