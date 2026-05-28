<#
.SYNOPSIS
运行仓库内 Bevy game 的 agent smoke 测试。

.DESCRIPTION
本脚本是 Bevy game 确定性 agent smoke 的标准入口。
当前会运行一个进程内 gameplay smoke：构造固定场景，定位可交互拾取物，
模拟 viewer 状态层的右键交互菜单路径，并断言世界交互菜单状态和 prompt。

.PARAMETER Scenario
要运行的 smoke 场景。当前支持 `WorldInteractionMenu`。

.PARAMETER OutputRoot
console log 和 JSON result 的输出目录。默认写入 `.local/agent-smoke/bevy_game`。

.EXAMPLE
pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1

.EXAMPLE
pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1 -Scenario WorldInteractionMenu

.NOTES
本 workflow 用于验证 gameplay 输入链路，不依赖 OS 窗口焦点、屏幕坐标或 OCR。
做人工窗口级检查前，优先运行这个确定性 smoke。
#>
param(
    [ValidateSet("WorldInteractionMenu")]
    [string]$Scenario = "WorldInteractionMenu",
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\agent-smoke\bevy_game"
}

$testFilters = @{
    WorldInteractionMenu = "agent_smoke_right_click_pickup_opens_interaction_menu"
}

$testFilter = $testFilters[$Scenario]
if ([string]::IsNullOrWhiteSpace($testFilter)) {
    throw "unsupported Bevy game smoke scenario: $Scenario"
}

$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$consoleLog = Join-Path $runRoot "console.log"
$resultPath = Join-Path $runRoot "result.json"
$startedAt = Get-Date
$status = "passed"
$exitCode = 0

Push-Location (Join-Path $repoRoot "legacy/bevy/rust")
try {
    Write-Host "Running Bevy game smoke scenario '$Scenario' with test filter '$testFilter'"
    & cargo test -p bevy_debug_viewer $testFilter -- --nocapture 2>&1 |
        Tee-Object -FilePath $consoleLog
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $status = "failed"
    }
}
finally {
    Pop-Location
}

$result = [PSCustomObject]@{
    scenario = $Scenario
    status = $status
    exitCode = $exitCode
    startedAt = $startedAt.ToString("o")
    finishedAt = (Get-Date).ToString("o")
    testFilter = $testFilter
    consoleLog = $consoleLog
}
$result | ConvertTo-Json -Depth 4 | Set-Content -Path $resultPath

if ($status -ne "passed") {
    Write-Error "Bevy game smoke failed; see $resultPath"
}

Write-Host "Bevy game smoke result written to $resultPath"
