Set-StrictMode -Version Latest

function Resolve-AgentGodotCommand {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Godot
    )

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Godot)) {
        $candidates += [PSCustomObject]@{ Source = "parameter"; Value = $Godot }
    }
    foreach ($scope in @("Process", "User", "Machine")) {
        $value = [Environment]::GetEnvironmentVariable("GODOT", $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $candidates += [PSCustomObject]@{ Source = "GODOT:$scope"; Value = $value }
        }
    }

    foreach ($name in @("godot", "godot.exe", "godot.cmd")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
            $candidates += [PSCustomObject]@{ Source = "PATH"; Value = $command.Source }
        }
    }

    $candidates += [PSCustomObject]@{ Source = "default"; Value = "D:\godot\godot.cmd" }

    foreach ($candidate in $candidates) {
        $resolved = Resolve-AgentGodotCandidate -Candidate $candidate.Value
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            return $resolved
        }
    }

    $attempts = ($candidates | ForEach-Object { "$($_.Source)=$($_.Value)" }) -join "; "
    throw "Godot command not found. Tried: $attempts"
}

function Resolve-AgentGodotCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return ""
    }

    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($Candidate)
    }

    if (Test-Path -LiteralPath $Candidate -PathType Container) {
        foreach ($fileName in @("godot.exe", "godot.cmd", "Godot.exe")) {
            $nested = Join-Path $Candidate $fileName
            if (Test-Path -LiteralPath $nested -PathType Leaf) {
                return [System.IO.Path]::GetFullPath($nested)
            }
        }
    }

    $command = Get-Command $Candidate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    return ""
}
