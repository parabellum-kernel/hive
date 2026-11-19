# Build (and optionally install) hive on Windows (PowerShell).
# Usage:
#   .\scripts\build-windows.ps1 [-Target <zig-triple>] [-Optimize <mode>] [-Install] [-Prefix <dir>]

param(
    [string]$Target = $(if ($env:HIVE_TARGET) { $env:HIVE_TARGET } else { "native" }),
    [string]$Optimize = $(if ($env:HIVE_OPTIMIZE) { $env:HIVE_OPTIMIZE } else { "ReleaseSafe" }),
    [switch]$Install,
    [string]$Prefix = $(if ($env:HIVE_PREFIX) { $env:HIVE_PREFIX } else { Join-Path $env:LOCALAPPDATA "hive" })
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $RootDir

try {
    $BuildArgs = @("-Doptimize=$Optimize")
    if ($Target -ne "native") {
        $BuildArgs += "-Dtarget=$Target"
    }

    Write-Host "==> Building hive for Windows (target=$Target, optimize=$Optimize)..."
    zig build @BuildArgs
    Write-Host "==> Built: $RootDir\zig-out\bin\hive.exe"

    if ($Install -or $PSBoundParameters.ContainsKey("Prefix")) {
        $BinDir = Join-Path $Prefix "bin"
        Write-Host "==> Installing hive to $BinDir\hive.exe..."
        zig build @BuildArgs --prefix $Prefix
        Write-Host "==> Installed: $BinDir\hive.exe"
        if (-not ($env:PATH -split ";" | Where-Object { $_ -eq $BinDir })) {
            Write-Host "Note: add '$BinDir' to your PATH to run 'hive' from any directory."
        }
    }
}
finally {
    Pop-Location
}
