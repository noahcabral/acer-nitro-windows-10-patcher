[CmdletBinding()]
param(
    [string]$LauncherDirectory = "C:\Program Files\NitroSense\Prerequisites",
    [string]$TargetExe = "$env:USERPROFILE\Desktop\NitroSense_portable_test\NitroSense.exe"
)

. (Join-Path $PSScriptRoot "Common.ps1")

Require-Administrator

$repoRoot = Get-RepoRoot
$sourceCandidates = @(
    (Join-Path $repoRoot "internal\templates\NitroSenseLauncherStub.cs"),
    (Join-Path $PSScriptRoot "NitroSenseLauncherStub.cs")
)
$launcherPath = Join-Path $LauncherDirectory "NitroSenseLauncher.exe"
$backupPath = "$launcherPath.appx-backup"
$configPath = Join-Path $LauncherDirectory "LauncherTarget.txt"
$buildPath = Join-Path $env:TEMP "NitroSenseLauncher.exe"
$compilerCandidates = @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "Could not find csc.exe"
}

Ensure-Directory -Path $LauncherDirectory

$sourcePath = $sourceCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $sourcePath) {
    throw "Source file not found. Checked: $($sourceCandidates -join ', ')"
}

if ((Test-Path -LiteralPath $launcherPath) -and -not (Test-Path -LiteralPath $backupPath)) {
    Move-Item -LiteralPath $launcherPath -Destination $backupPath -Force
}

& $compiler /nologo /target:winexe /out:$buildPath $sourcePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $buildPath)) {
    throw "Failed to compile NitroSenseLauncher stub."
}

Copy-Item -LiteralPath $buildPath -Destination $launcherPath -Force
Write-Utf8NoBomFile -Path $configPath -Content ([System.IO.Path]::GetFullPath($TargetExe))

Write-Host "Installed launcher stub at $launcherPath"
Write-Host "Target set to $TargetExe"
