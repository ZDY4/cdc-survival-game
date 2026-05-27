<#
.SYNOPSIS
Runs the Godot content CLI for repo-local content inspection and validation.

.DESCRIPTION
Wraps `D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/content_cli.gd -- ...`.
This is the Godot migration replacement path for common `content_tools` locate,
summarize, references, validate, format, and diff-summary commands.

.PARAMETER Command
Content command to run: locate, summarize, references, validate, format, or diff-summary.

.PARAMETER Kind
Content kind such as item, recipe, character, dialogue, quest, skill, skill_tree, map,
changed for `validate changed` / `format changed`, or path for `diff-summary --path`.

.PARAMETER Id
Content id for locate/summarize/references/validate/format, or the path for diff-summary.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind item -Id 1006

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind map -Id survivor_outpost_01

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind item -Id 1006

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind skill_tree -Id survival

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command diff-summary -Kind path -Id data/items/1006.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("locate", "summarize", "references", "validate", "format", "diff-summary")]
    [string]$Command,

    [Parameter(Mandatory = $true)]
    [string]$Kind,

    [Parameter(Mandatory = $false)]
    [string]$Id,

    [Parameter(Mandatory = $false)]
    [string]$Godot = "D:\godot\godot.cmd"
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

if ($Command -eq "diff-summary") {
    if ($Kind -ne "path") {
        throw "Use -Kind path with -Command diff-summary"
    }
    if ([string]::IsNullOrWhiteSpace($Id)) {
        throw "-Command diff-summary requires -Id <repo-relative-or-absolute-path>"
    }
    $contentArgs = @($Command, "--path", $Id)
} else {
    $contentArgs = @($Command, $Kind)
    if ($PSBoundParameters.ContainsKey("Id") -and -not [string]::IsNullOrWhiteSpace($Id)) {
        $contentArgs += $Id
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
