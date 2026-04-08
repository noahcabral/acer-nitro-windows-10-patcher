[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$AsarPath,
    [string]$OutputRoot = (Join-Path (Get-Location) "internal\build\asar-extracted"),
    [string]$WorkRoot = (Join-Path (Get-Location) "internal\build\appx-unpacked")
)

. (Join-Path $PSScriptRoot "Common.ps1")

Ensure-Directory -Path (Split-Path -Parent $OutputRoot)

if (-not $AsarPath) {
    if (-not $PackageRoot) {
        throw "Specify either -AsarPath or -PackageRoot."
    }

    $appxPath = Get-MainUwpAppxPath -PackageRoot $PackageRoot
    Expand-AppxToFolder -AppxPath $appxPath -Destination $WorkRoot

    $AsarPath = Join-Path $WorkRoot "app\resources\app.asar"
    if (-not (Test-Path -LiteralPath $AsarPath)) {
        throw "Could not find app.asar in $WorkRoot"
    }
}

if (-not (Test-Path -LiteralPath $AsarPath)) {
    throw "ASAR file not found: $AsarPath"
}

Write-Host "Extracting app.asar to $OutputRoot"
Extract-AsarArchive -AsarPath $AsarPath -Destination $OutputRoot

Write-Host "Done: $OutputRoot"
