<#
.SYNOPSIS
Runs the Godot content CLI for repo-local content inspection and validation.

.DESCRIPTION
Wraps `D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/content_cli.gd`.
This is the Godot migration replacement path for common `content_tools` locate,
summarize, references, and validate commands.

.PARAMETER Command
Content command to run: locate, summarize, references, or validate.

.PARAMETER Kind
Content kind such as item, recipe, character, map, or changed for `validate changed`.

.PARAMETER Id
Content id for locate/summarize/references/validate.

.PARAMETER Godot
Path to the Godot command line entrypoint.

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind item -Id 1006

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind map -Id survivor_outpost_01

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("locate", "summarize", "references", "validate")]
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

$contentArgs = @($Command, $Kind)
if ($PSBoundParameters.ContainsKey("Id") -and -not [string]::IsNullOrWhiteSpace($Id)) {
    $contentArgs += $Id
}

Push-Location $repoRoot
try {
    & $Godot --headless --path godot --script "res://scripts/tools/content_cli.gd" @contentArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Godot content CLI failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
