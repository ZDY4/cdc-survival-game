param(
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $root "build"
$vsDevCmd = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat"

if (-not (Test-Path $vsDevCmd)) {
    throw "VsDevCmd.bat not found at $vsDevCmd"
}

$configure = @"
call "$vsDevCmd" -arch=x64
cmake -S "$root" -B "$buildDir" -G "Visual Studio 18 2026" -A x64
"@

$build = @"
call "$vsDevCmd" -arch=x64
cmake --build "$buildDir" --config $Configuration
"@

cmd /c $configure
cmd /c $build
