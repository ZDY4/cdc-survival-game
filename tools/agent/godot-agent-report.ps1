<#
.SYNOPSIS
Writes agent-readable Godot script and scene reports.

.DESCRIPTION
This script summarizes GDScript files and Godot scenes into reports under
`.local/agent-reports/godot`. It adapts the useful CODEXVault_GODOT gather-tool
idea to this repo-local PowerShell workflow without writing temporary files into
the Godot project directory.

.PARAMETER Kind
Report kind to generate. Use `All` to generate Scripts and Scenes reports.

.PARAMETER OutputRoot
Directory for generated reports. Defaults to `.local/agent-reports/godot`.

.PARAMETER IncludeSource
When used with Scripts or All, also writes a source compilation text file.

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scripts

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scenes

.EXAMPLE
pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind All -IncludeSource
#>
[CmdletBinding()]
param(
    [ValidateSet("All", "Scripts", "Scenes")]
    [string]$Kind = "All",

    [string]$OutputRoot,

    [switch]$IncludeSource
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$godotRoot = Join-Path $repoRoot "godot"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".local\agent-reports\godot"
}
if (-not (Test-Path -LiteralPath $godotRoot)) {
    throw "Godot project not found: $godotRoot"
}

$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

function ConvertTo-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetRelativePath($repoRoot, [System.IO.Path]::GetFullPath($Path)).Replace("\", "/")
}

function ConvertTo-GodotResourcePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $relative = [System.IO.Path]::GetRelativePath($godotRoot, $fullPath).Replace("\", "/")
    return "res://$relative"
}

function Get-FirstRegexGroup {
    param(
        [AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    foreach ($line in $Lines) {
        if ($line -match $Pattern) {
            return $Matches[1]
        }
    }
    return ""
}

function Get-GdScriptSummary {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)
    $lines = @(Get-Content -LiteralPath $File.FullName)
    $preloads = @()
    $consts = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match 'preload\("([^"]+)"\)') {
            $preloads += [PSCustomObject]@{
                line = $i + 1
                path = $Matches[1]
                text = $line.Trim()
            }
        }
        if ($line -match '^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)') {
            $consts += [PSCustomObject]@{
                line = $i + 1
                name = $Matches[1]
                text = $line.Trim()
            }
        }
    }
    return [PSCustomObject]@{
        path = ConvertTo-RepoRelativePath $File.FullName
        resourcePath = ConvertTo-GodotResourcePath $File.FullName
        lineCount = $lines.Count
        className = Get-FirstRegexGroup $lines '^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)'
        extends = Get-FirstRegexGroup $lines '^\s*extends\s+(.+?)\s*$'
        preloads = @($preloads | Select-Object -First 20)
        consts = @($consts | Select-Object -First 20)
    }
}

function Write-ScriptsReport {
    $scriptFiles = @(Get-ChildItem -LiteralPath $godotRoot -Recurse -Filter "*.gd" -File | Sort-Object FullName)
    $summaries = @($scriptFiles | ForEach-Object { Get-GdScriptSummary $_ })

    $jsonPath = Join-Path $runRoot "scripts-summary.json"
    $markdownPath = Join-Path $runRoot "scripts-summary.md"
    [PSCustomObject]@{
        generatedAt = (Get-Date).ToString("o")
        scriptCount = $summaries.Count
        scripts = $summaries
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath

    $md = @()
    $md += "# Godot Script Summary"
    $md += ""
    $md += "- Generated: $((Get-Date).ToString("o"))"
    $md += "- Script count: $($summaries.Count)"
    $md += ""
    foreach ($script in $summaries) {
        $titleBits = @($script.path)
        if (-not [string]::IsNullOrWhiteSpace($script.className)) {
            $titleBits += "class_name=$($script.className)"
        }
        if (-not [string]::IsNullOrWhiteSpace($script.extends)) {
            $titleBits += "extends=$($script.extends)"
        }
        $md += "## $($titleBits -join ' | ')"
        $md += "- Lines: $($script.lineCount)"
        if ($script.preloads.Count -gt 0) {
            $md += "- Preloads:"
            foreach ($preload in $script.preloads) {
                $md += "  - L$($preload.line): $($preload.path)"
            }
        }
        if ($script.consts.Count -gt 0) {
            $md += "- Consts:"
            foreach ($const in $script.consts) {
                $md += "  - L$($const.line): $($const.name)"
            }
        }
        $md += ""
    }
    $md | Set-Content -Path $markdownPath

    $sourcePath = ""
    if ($IncludeSource) {
        $sourcePath = Join-Path $runRoot "scripts-source.txt"
        foreach ($file in $scriptFiles) {
            Add-Content -Path $sourcePath -Value ("`n--- Script: {0} ---" -f (ConvertTo-RepoRelativePath $file.FullName))
            Get-Content -LiteralPath $file.FullName | Add-Content -Path $sourcePath
        }
    }

    return [PSCustomObject]@{
        kind = "Scripts"
        status = "written"
        json = $jsonPath
        markdown = $markdownPath
        source = $sourcePath
        count = $summaries.Count
    }
}

function ConvertTo-AttributeMap {
    param([Parameter(Mandatory = $true)][string]$AttributeText)
    $attributes = @{}
    $matches = [regex]::Matches($AttributeText, '([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|[^\s\]]+)')
    foreach ($match in $matches) {
        $value = $match.Groups[2].Value
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $attributes[$match.Groups[1].Value] = $value
    }
    return $attributes
}

function Resolve-ExtResourcePath {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Resources,
        [string]$Reference
    )
    if ([string]::IsNullOrWhiteSpace($Reference)) {
        return ""
    }
    if ($Reference -match 'ExtResource\("([^"]+)"\)') {
        $resourceId = $Matches[1]
        if ($Resources.ContainsKey($resourceId)) {
            return $Resources[$resourceId].path
        }
    }
    return $Reference
}

function Get-SceneSummary {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)
    $lines = Get-Content -LiteralPath $File.FullName
    $resources = @{}
    $nodes = @()
    $currentNode = $null

    foreach ($line in $lines) {
        if ($line -match '^\[ext_resource\s+(.+)\]') {
            $attrs = ConvertTo-AttributeMap $Matches[1]
            if ($attrs.ContainsKey("id")) {
                $resources[$attrs["id"]] = [PSCustomObject]@{
                    id = $attrs["id"]
                    type = if ($attrs.ContainsKey("type")) { $attrs["type"] } else { "" }
                    path = if ($attrs.ContainsKey("path")) { $attrs["path"] } else { "" }
                }
            }
            continue
        }

        if ($line -match '^\[node\s+(.+)\]') {
            $attrs = ConvertTo-AttributeMap $Matches[1]
            $name = if ($attrs.ContainsKey("name")) { $attrs["name"] } else { "" }
            $parent = if ($attrs.ContainsKey("parent")) { $attrs["parent"] } else { "" }
            $nodePath = $name
            if (-not [string]::IsNullOrWhiteSpace($parent) -and $parent -ne ".") {
                $nodePath = "$parent/$name"
            }
            $instanceRef = if ($attrs.ContainsKey("instance")) { $attrs["instance"] } else { "" }
            $currentNode = [PSCustomObject]@{
                name = $name
                type = if ($attrs.ContainsKey("type")) { $attrs["type"] } else { "" }
                parent = $parent
                path = $nodePath
                instance = Resolve-ExtResourcePath $resources $instanceRef
                script = ""
            }
            $nodes += $currentNode
            continue
        }

        if ($currentNode -ne $null -and $line -match '^\s*script\s*=\s*(ExtResource\("[^"]+"\))') {
            $currentNode.script = Resolve-ExtResourcePath $resources $Matches[1]
        }
    }

    return [PSCustomObject]@{
        path = ConvertTo-RepoRelativePath $File.FullName
        resourcePath = ConvertTo-GodotResourcePath $File.FullName
        lineCount = $lines.Count
        extResources = @($resources.Values | Sort-Object id)
        nodes = $nodes
        nodeCount = $nodes.Count
        scriptedNodeCount = @($nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_.script) }).Count
        instancedNodeCount = @($nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_.instance) }).Count
    }
}

function Write-ScenesReport {
    $sceneRoot = Join-Path $godotRoot "scenes"
    $sceneFiles = @()
    if (Test-Path -LiteralPath $sceneRoot) {
        $sceneFiles = @(Get-ChildItem -LiteralPath $sceneRoot -Recurse -Include "*.tscn", "*.scn" -File | Sort-Object FullName)
    }
    $summaries = @($sceneFiles | ForEach-Object { Get-SceneSummary $_ })

    $jsonPath = Join-Path $runRoot "scenes-summary.json"
    $markdownPath = Join-Path $runRoot "scenes-summary.md"
    [PSCustomObject]@{
        generatedAt = (Get-Date).ToString("o")
        sceneCount = $summaries.Count
        scenes = $summaries
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath

    $md = @()
    $md += "# Godot Scene Summary"
    $md += ""
    $md += "- Generated: $((Get-Date).ToString("o"))"
    $md += "- Scene count: $($summaries.Count)"
    $md += ""
    foreach ($scene in $summaries) {
        $md += "## $($scene.path)"
        $md += "- Lines: $($scene.lineCount)"
        $md += "- Nodes: $($scene.nodeCount)"
        $md += "- Scripted nodes: $($scene.scriptedNodeCount)"
        $md += "- Instanced nodes: $($scene.instancedNodeCount)"
        if ($scene.extResources.Count -gt 0) {
            $md += "- External resources:"
            foreach ($resource in $scene.extResources) {
                $md += "  - $($resource.id): $($resource.type) $($resource.path)"
            }
        }
        if ($scene.nodes.Count -gt 0) {
            $md += "- Nodes:"
            foreach ($node in $scene.nodes) {
                $bits = @($node.path)
                if (-not [string]::IsNullOrWhiteSpace($node.type)) {
                    $bits += "type=$($node.type)"
                }
                if (-not [string]::IsNullOrWhiteSpace($node.script)) {
                    $bits += "script=$($node.script)"
                }
                if (-not [string]::IsNullOrWhiteSpace($node.instance)) {
                    $bits += "instance=$($node.instance)"
                }
                $md += "  - $($bits -join ' | ')"
            }
        }
        $md += ""
    }
    $md | Set-Content -Path $markdownPath

    return [PSCustomObject]@{
        kind = "Scenes"
        status = "written"
        json = $jsonPath
        markdown = $markdownPath
        count = $summaries.Count
    }
}

$results = @()
if ($Kind -eq "All" -or $Kind -eq "Scripts") {
    $results += Write-ScriptsReport
}
if ($Kind -eq "All" -or $Kind -eq "Scenes") {
    $results += Write-ScenesReport
}

$resultPath = Join-Path $runRoot "result.json"
[PSCustomObject]@{
    kind = $Kind
    generatedAt = (Get-Date).ToString("o")
    outputRoot = $runRoot
    results = $results
} | ConvertTo-Json -Depth 6 | Set-Content -Path $resultPath

Write-Host "Godot agent report written to $runRoot"
Write-Host "Result JSON: $resultPath"
