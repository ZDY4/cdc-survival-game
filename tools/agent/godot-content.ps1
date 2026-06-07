<#
.SYNOPSIS
Runs the Godot content CLI for repo-local content inspection and validation.

.DESCRIPTION
Wraps `D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/content_cli.gd -- ...`.
This is the Godot migration replacement path for common `content_tools` locate,
summarize, references, validate, format, diff-summary, and asset-manifest commands.
`validate changed` filters Git status to migrated content domains and prints a
`change_status_summary` line for modified / added / untracked / deleted / renamed records.
`diff-summary changed` prints per-file line/hunk counts plus aggregate totals for the same changed content scope.
`format -DryRun` reports whether records would be rewritten without touching files.
`fix changed` batches safe content repairs; the first Godot implementation applies JSON formatting and reports pending schema migrations.

.PARAMETER Command
Content command to run: locate, summarize, references, validate, format, fix, diff-summary, or asset-manifest.

.PARAMETER Kind
Content kind such as item, recipe, character, dialogue, dialogue_rule, quest, skill, skill_tree,
settlement, overworld, map, shop, world_tile, appearance, ai, json, changed for `validate changed` / `format changed`,
changed for `diff-summary changed`, all for `asset-manifest all`, or path for `diff-summary --path`.

.PARAMETER Id
Content id for locate/summarize/references/validate/format, or the path for diff-summary.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.PARAMETER DryRun
Preview `format` / `format changed` / `fix changed` rewrites without writing files.

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind item -Id 1006

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind map -Id survivor_outpost_01

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed

Runs validation for supported changed content files and reports changed file counts by Git status.

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind item -Id 1006

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind changed -DryRun

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command fix -Kind changed -DryRun

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind skill_tree -Id survival

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind settlement -Id survivor_outpost_01_settlement

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind overworld -Id main_overworld

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command diff-summary -Kind changed

Reports diff totals for all supported changed content files.

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command diff-summary -Kind path -Id data/items/1006.json

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command asset-manifest -Kind all
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("locate", "summarize", "references", "validate", "format", "fix", "diff-summary", "asset-manifest")]
    [string]$Command,

    [Parameter(Mandatory = $true)]
    [string]$Kind,

    [Parameter(Mandatory = $false)]
    [string]$Id,

    [Parameter(Mandatory = $false)]
    [string]$Godot = "D:\godot\godot.cmd",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$godotProject = Join-Path $repoRoot "godot"
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot command not found: $Godot"
}
if (-not (Test-Path -LiteralPath $godotProject)) {
    throw "Godot project not found: $godotProject"
}
if ($DryRun -and $Command -notin @("format", "fix")) {
    throw "-DryRun is only supported with -Command format or -Command fix"
}

if ($Command -eq "diff-summary") {
    if ($Kind -eq "changed") {
        $contentArgs = @($Command, "changed")
    } elseif ($Kind -eq "path") {
        if ([string]::IsNullOrWhiteSpace($Id)) {
            throw "-Command diff-summary -Kind path requires -Id <repo-relative-or-absolute-path>"
        }
        $contentArgs = @($Command, "--path", $Id)
    } else {
        throw "Use -Kind changed or -Kind path with -Command diff-summary"
    }
} elseif ($Command -eq "asset-manifest") {
    if ($Kind -ne "all") {
        throw "Use -Kind all with -Command asset-manifest"
    }
    $contentArgs = @($Command, "all")
} else {
    $contentArgs = @($Command, $Kind)
    if ($PSBoundParameters.ContainsKey("Id") -and -not [string]::IsNullOrWhiteSpace($Id)) {
        $contentArgs += $Id
    }
    if ($DryRun) {
        $contentArgs += "--dry-run"
    }
}

Push-Location $repoRoot
try {
    & $Godot --headless --path godot --script "res://scripts/tools/content_cli.gd" -- @contentArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Godot content CLI failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
