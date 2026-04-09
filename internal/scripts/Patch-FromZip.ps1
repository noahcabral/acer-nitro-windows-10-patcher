[CmdletBinding()]
param(
    [string]$InputDir = (Join-Path (Get-Location) "input"),
    [string]$OutputDir = (Join-Path (Get-Location) "output"),
    [string]$WorkDir = (Join-Path (Get-Location) "internal\work\patch-run")
)

. (Join-Path $PSScriptRoot "Common.ps1")

$repoRoot = Get-RepoRoot
$inputDir = [System.IO.Path]::GetFullPath($InputDir)
$outputDir = [System.IO.Path]::GetFullPath($OutputDir)
$workDir = [System.IO.Path]::GetFullPath($WorkDir)

Ensure-Directory -Path $inputDir
Ensure-Directory -Path (Split-Path -Parent $outputDir)
Ensure-Directory -Path (Split-Path -Parent $workDir)

$stoppedOutputProcesses = @(Stop-ProcessesFromPathPrefix -PathPrefix $outputDir)
if ($stoppedOutputProcesses.Count -gt 0) {
    Write-Host "Closed running app(s) from output:"
    $stoppedOutputProcesses | ForEach-Object {
        Write-Host ("- {0} ({1})" -f $_.ProcessName, $_.Id)
    }
    Write-Host ""
}

$zipFiles = @(Get-ChildItem -LiteralPath $inputDir -File | Where-Object { $_.Extension -ieq ".zip" })
$inputDirectories = @(Get-ChildItem -LiteralPath $inputDir -Directory | Where-Object { $_.Name -ne '.gitkeep' })

if (($zipFiles.Count -gt 0) -and ($inputDirectories.Count -gt 0)) {
    throw "Found both zip file(s) and folder(s) in $inputDir. Keep only one source there and run patch.bat again."
}

if ($zipFiles.Count -gt 1) {
    $names = ($zipFiles | Select-Object -ExpandProperty Name) -join ", "
    throw "More than one zip was found in $inputDir ($names). Keep only one zip there and run patch.bat again."
}

$expandedRoot = Join-Path $workDir "expanded-zip"
$asarRoot = Join-Path $workDir "asar-extracted"
$portableOut = Join-Path $outputDir "NitroSense_portable"
$backendOut = Join-Path $outputDir "Backend"
$toolsOut = Join-Path $outputDir "tools"
$appxWork = Join-Path $workDir "appx-work"

Reset-Directory -Path $expandedRoot
Reset-Directory -Path $asarRoot
Reset-Directory -Path $outputDir

if ($zipFiles.Count -eq 1) {
    $sourceDescription = $zipFiles[0].Name
    $zipPath = $zipFiles[0].FullName
    Write-Host "[1/5] Extracting zip: $zipPath"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $expandedRoot -Force
    $packageRoot = Get-PackageRootFromExpandedZip -ExpandedRoot $expandedRoot
} elseif ($inputDirectories.Count -eq 1) {
    $sourceDescription = $inputDirectories[0].Name
    $sourceRoot = $inputDirectories[0].FullName
    Write-Host "[1/5] Using extracted folder: $sourceRoot"
    $packageRoot = Get-PackageRootFromExpandedZip -ExpandedRoot $sourceRoot
} else {
    throw "No patch source was found in $inputDir. Put exactly one NitroSense zip or one extracted NitroSense folder there and run patch.bat again."
}

Write-Host "[2/5] Package root found: $packageRoot"

$appxPath = Get-MainUwpAppxPath -PackageRoot $packageRoot
$expandedAppxRoot = Join-Path $workDir "appx-unpacked"
Expand-AppxToFolder -AppxPath $appxPath -Destination $expandedAppxRoot
$asarPath = Join-Path $expandedAppxRoot "app\resources\app.asar"

Write-Host "[3/5] Extracting app.asar"
Extract-AsarArchive -AsarPath $asarPath -Destination $asarRoot

Write-Host "[4/5] Building portable NitroSense"
& (Join-Path $PSScriptRoot "Build-Portable.ps1") `
    -PackageRoot $packageRoot `
    -AsarExtractedRoot $asarRoot `
    -OutputRoot $portableOut `
    -WorkRoot $appxWork

Write-Host "[5/5] Preparing backend/tool output"
Ensure-Directory -Path $backendOut
Ensure-Directory -Path $toolsOut

foreach ($folder in @("AgentService", "AcerSystemMonitorService", "AcerQAAgent", "AcerCCAgent", "UWP")) {
    $src = Join-Path $packageRoot $folder
    if (Test-Path -LiteralPath $src) {
        Copy-DirectoryContents -Source $src -Destination (Join-Path $backendOut $folder)
    }
}

foreach ($file in @("Common.ps1", "Install-Backend.ps1", "Register-NitroLauncher.ps1", "Create-DesktopShortcut.ps1", "Tidy-NitroConfig.ps1", "Install-NitroLauncherStub.ps1")) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $toolsOut $file) -Force
}

Copy-Item -LiteralPath (Join-Path $repoRoot "internal\templates\NitroSenseLauncherStub.cs") -Destination (Join-Path $toolsOut "NitroSenseLauncherStub.cs") -Force

$readme = @"
NitroSense Win10 output
=======================

Source:
$sourceDescription

Contents:
- NitroSense_portable : patched portable frontend
- Backend             : backend source files copied from the original Acer package
- tools               : helper PowerShell scripts

Suggested next steps:
1. Open NitroSense_portable and inspect the patched app files.
   NitroSense's packaged Store-version path is neutralized in this build, and the Live Update widget is removed from the profile config.
2. If you want to install the backend on a Windows 10 machine, open an elevated PowerShell in the tools folder and run:
   .\Install-Backend.ps1 -PackageRoot ..\Backend
3. Re-register the launcher / desktop shortcut if needed with:
   .\Register-NitroLauncher.ps1 -PortableRoot ..\NitroSense_portable
   .\Create-DesktopShortcut.ps1 -PortableRoot ..\NitroSense_portable
4. If the Nitro key still points to Acer's old packaged launcher, replace it with the wrapper using:
   .\Install-NitroLauncherStub.ps1 -TargetExe ..\NitroSense_portable\NitroSense.exe
"@
Write-Utf8NoBomFile -Path (Join-Path $outputDir "README.txt") -Content $readme

Write-Host ""
Write-Host "Done."
Write-Host "Output folder: $outputDir"
