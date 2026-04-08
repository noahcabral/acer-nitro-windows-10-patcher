[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot,
    [Parameter(Mandatory = $true)]
    [string]$AsarExtractedRoot,
    [string]$OutputRoot = (Join-Path (Get-Location) "internal\build\NitroSense_portable"),
    [string]$WorkRoot = (Join-Path (Get-Location) "internal\build\appx-portable-source")
)

. (Join-Path $PSScriptRoot "Common.ps1")

if (-not (Test-Path -LiteralPath $AsarExtractedRoot)) {
    throw "Asar extracted root not found: $AsarExtractedRoot"
}

if (-not (Test-Path -LiteralPath (Join-Path $AsarExtractedRoot "package.json"))) {
    throw "Asar extracted root does not look correct. package.json is missing."
}

$repoRoot = Get-RepoRoot
$appxPath = Get-MainUwpAppxPath -PackageRoot $PackageRoot
Expand-AppxToFolder -AppxPath $appxPath -Destination $WorkRoot

$portableSourceRoot = Join-Path $WorkRoot "app"
if (-not (Test-Path -LiteralPath $portableSourceRoot)) {
    throw "Extracted AppX did not contain an app folder."
}

Reset-Directory -Path $OutputRoot
Copy-DirectoryContents -Source $portableSourceRoot -Destination $OutputRoot

$resourcesRoot = Join-Path $OutputRoot "resources"
$asarPath = Join-Path $resourcesRoot "app.asar"
$asarOriginalPath = Join-Path $resourcesRoot "app.asar.original"
$asarUnpackedRoot = Join-Path $resourcesRoot "app.asar.unpacked"
$unpackedAppRoot = Join-Path $resourcesRoot "app"
$appMainPath = Join-Path $unpackedAppRoot "main.js"
$indexHtmlPath = Join-Path $unpackedAppRoot "dist\widgets\main\index.html"

if (-not (Test-Path -LiteralPath $asarPath)) {
    throw "resources\\app.asar was not found in $OutputRoot"
}

if (Test-Path -LiteralPath $asarOriginalPath) {
    Remove-Item -LiteralPath $asarOriginalPath -Force
}

Move-Item -LiteralPath $asarPath -Destination $asarOriginalPath

if (Test-Path -LiteralPath $unpackedAppRoot) {
    Remove-Item -LiteralPath $unpackedAppRoot -Recurse -Force
}

Copy-DirectoryContents -Source $AsarExtractedRoot -Destination $unpackedAppRoot
Normalize-PercentEncodedNames -RootPath (Join-Path $OutputRoot "win32")

$nativeNodeModulesRoot = Join-Path $asarUnpackedRoot "node_modules"
$targetNodeModulesRoot = Join-Path $unpackedAppRoot "node_modules"
if (Test-Path -LiteralPath $nativeNodeModulesRoot) {
    Ensure-Directory -Path $targetNodeModulesRoot
    Get-ChildItem -LiteralPath $nativeNodeModulesRoot | ForEach-Object {
        $targetPath = Join-Path $targetNodeModulesRoot $_.Name
        if ($_.PSIsContainer) {
            if (Test-Path -LiteralPath $targetPath) {
                Copy-DirectoryContents -Source $_.FullName -Destination $targetPath
            } else {
                Copy-Item -LiteralPath $_.FullName -Destination $targetPath -Recurse -Force
            }
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $targetPath -Force
        }
    }
}

$mainJs = Get-Content -LiteralPath $appMainPath -Raw
$mainJs = $mainJs.Replace("this.showWhenReady=!!this.devMode||this.forceShow", "this.showWhenReady=!0")
$mainJs = $mainJs.Replace("this.checkNewStoreVersion(),this.readOEMSettings()", "this.hasStoreNewerVersion=A.NoNewerVersion,this.readOEMSettings()")
$mainJs = $mainJs.Replace("t.isMinimized()||!t.isVisible()?(c.app.relaunch(),c.app.exit(-1)):g.EnvConfig.getInstance().pendingReloadContent=!0", "g.EnvConfig.getInstance().pendingReloadContent=!0")
Write-Utf8NoBomFile -Path $appMainPath -Content $mainJs

$storeShimRoot = Join-Path $unpackedAppRoot "node_modules\@nodert-win10-rs4\windows.services.store"
$enumShimRoot = Join-Path $unpackedAppRoot "node_modules\@nodert-win10-rs4\windows.devices.enumeration"

Copy-DirectoryContents -Source (Join-Path $repoRoot "internal\templates\shims\windows.services.store") -Destination $storeShimRoot
Copy-DirectoryContents -Source (Join-Path $repoRoot "internal\templates\shims\windows.devices.enumeration") -Destination $enumShimRoot

$indexHtml = Get-Content -LiteralPath $indexHtmlPath -Raw
if ($indexHtml -notmatch "ns-mode-fallback-panel") {
    $injection = Get-Content -LiteralPath (Join-Path $repoRoot "internal\templates\portable-ui-inject.html") -Raw
    $indexHtml = $indexHtml -replace "</body></html>$", ($injection + "`r`n</body></html>")
    Write-Utf8NoBomFile -Path $indexHtmlPath -Content $indexHtml
}

Write-Host "Portable build created at $OutputRoot"
