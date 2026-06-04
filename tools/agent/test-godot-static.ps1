<#
.SYNOPSIS
Runs Godot static validation scenarios for the repo.

.DESCRIPTION
This script is the repo-local agent entrypoint for Godot import/cache warmup and
GDScript static parsing checks. It adapts the useful CODEXVault_GODOT headless
validation loop to this Windows + GDScript project without adding Mono, .NET,
pre-commit, or Linux setup dependencies.

.PARAMETER Scenario
Static validation scenario to run. Use `All` to run Import and CheckOnly.

.PARAMETER OutputRoot
Directory for console logs and JSON result output. Defaults to `.local/agent-smoke/godot_static`.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-static.ps1

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario Import

.EXAMPLE
pwsh -NoProfile -File tools/agent/test-godot-static.ps1 -Scenario CheckOnly
#>
[CmdletBinding()]
param(
    [ValidateSet("All", "Import", "CheckOnly")]
    [string]$Scenario = "All",

    [string]$OutputRoot,

    [string]$Godot = "D:\godot\godot.cmd"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$godotProject = Join-Path $repoRoot "godot"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\agent-smoke\godot_static"
}
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot command not found: $Godot"
}
if (-not (Test-Path -LiteralPath $godotProject)) {
    throw "Godot project not found: $godotProject"
}

$scenarioCommands = [ordered]@{
    Import = @{
        Args = @("--headless", "--editor", "--import", "--quit", "--path", "godot")
        Description = "Warm Godot import cache and script-class cache."
    }
    CheckOnly = @{
        Description = "Parse/check every GDScript file without running the game."
    }
}

$selected = @()
if ($Scenario -eq "All") {
    $selected = @($scenarioCommands.Keys)
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
        $scenarioConfig = $scenarioCommands[$name]
        $consoleLog = Join-Path $runRoot ("{0}.log" -f $name)
        Write-Host "Running Godot static scenario '$name': $($scenarioConfig.Description)"

        $exitCode = 0
        $checkedScripts = 0
        $failedScripts = @()
        if ($name -eq "CheckOnly") {
            $scriptFiles = @(Get-ChildItem -LiteralPath $godotProject -Recurse -Filter "*.gd" -File | Sort-Object FullName)
            "Checking $($scriptFiles.Count) GDScript files." | Tee-Object -FilePath $consoleLog
            foreach ($scriptFile in $scriptFiles) {
                $relative = [System.IO.Path]::GetRelativePath($godotProject, $scriptFile.FullName).Replace("\", "/")
                $resourcePath = "res://$relative"
                $args = @("--headless", "--path", "godot", "--check-only", "--script", $resourcePath)
                $checkedScripts += 1
                "Command: $Godot $($args -join ' ')" | Tee-Object -FilePath $consoleLog -Append
                & $Godot @args 2>&1 | Tee-Object -FilePath $consoleLog -Append
                $scriptExitCode = $LASTEXITCODE
                if ($scriptExitCode -ne 0) {
                    $exitCode = $scriptExitCode
                    $failedScripts += [PSCustomObject]@{
                        script = $resourcePath
                        exitCode = $scriptExitCode
                    }
                    break
                }
            }
        } else {
            $args = @($scenarioConfig.Args)
            Write-Host "Command: $Godot $($args -join ' ')"
            & $Godot @args 2>&1 | Tee-Object -FilePath $consoleLog
            $exitCode = $LASTEXITCODE
        }

        $scenarioStatus = if ($exitCode -eq 0) { "passed" } else { "failed" }
        if ($exitCode -ne 0) {
            $status = "failed"
        }
        $results += [PSCustomObject]@{
            scenario = $name
            status = $scenarioStatus
            exitCode = $exitCode
            checkedScripts = $checkedScripts
            failedScripts = $failedScripts
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
    Write-Error "Godot static validation failed; see $resultPath"
}

Write-Host "Godot static validation result written to $resultPath"
