[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path (Get-RepoRoot) "output"),
    [string]$InstallRoot = "$env:ProgramFiles\NitroSense"
)

. (Join-Path $PSScriptRoot "Common.ps1")

Require-Administrator

function Test-DriverOriginalNamePresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OriginalInfName
    )

    $output = & pnputil.exe /enum-drivers 2>&1 | Out-String
    return $output -match ("Original Name:\s+" + [regex]::Escape($OriginalInfName))
}

$repoRoot = Get-RepoRoot
$outputDir = [System.IO.Path]::GetFullPath($OutputDir)
$installRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$portableSource = Join-Path $outputDir "NitroSense_portable"
$backendRoot = Join-Path $outputDir "Backend"
$toolsRoot = Join-Path $outputDir "tools"
$installParent = Split-Path -Parent $installRoot
$workRoot = Join-Path $repoRoot "internal\work\install-run"

if (-not (Test-Path -LiteralPath $portableSource)) {
    throw "Portable output not found: $portableSource"
}

if (-not (Test-Path -LiteralPath $backendRoot)) {
    throw "Backend output not found: $backendRoot"
}

if (-not (Test-Path -LiteralPath $toolsRoot)) {
    throw "Tools output not found: $toolsRoot"
}

$requiredPatchedExtensions = @(
    @{
        OriginalInf = "sysmonitorserviceextension.inf"
        FriendlyName = "Acer System Monitor Service Extension"
    },
    @{
        OriginalInf = "acerqa_ext.inf"
        FriendlyName = "Acer Quick Access Extension"
    },
    @{
        OriginalInf = "acercc_ext.inf"
        FriendlyName = "Acer Care Center Extension"
    }
)

$missingPatchedExtensions = @(
    $requiredPatchedExtensions | Where-Object {
        -not (Test-DriverOriginalNamePresent -OriginalInfName $_.OriginalInf)
    }
)

if ($missingPatchedExtensions.Count -gt 0) {
    Write-Warning "Preflight: the following extension driver(s) are not currently present in the driver store:"
    $missingPatchedExtensions | ForEach-Object {
        Write-Warning ("- {0} ({1})" -f $_.FriendlyName, $_.OriginalInf)
    }
    Write-Warning "This install may later need the patched unsigned INF packages for those drivers."
    Write-Warning "If Windows rejects them, reboot once with 'Disable driver signature enforcement' and rerun install.bat."
    Write-Host ""
} else {
    Write-Host "Preflight: required extension drivers are already present in the driver store."
    Write-Host ""
}

Ensure-Directory -Path $installParent
Ensure-Directory -Path $workRoot

$stoppedInstalled = @(Stop-ProcessesFromPathPrefix -PathPrefix $installRoot)
$stoppedOutput = @(Stop-ProcessesFromPathPrefix -PathPrefix $portableSource)

if ($stoppedInstalled.Count -gt 0 -or $stoppedOutput.Count -gt 0) {
    Write-Host "Closed running NitroSense process(es)."
}

Reset-Directory -Path $installRoot
Copy-DirectoryContents -Source $portableSource -Destination $installRoot

& (Join-Path $toolsRoot "Install-Backend.ps1") -PackageRoot $backendRoot -WorkRoot (Join-Path $workRoot "backend")
& (Join-Path $toolsRoot "Register-NitroLauncher.ps1") -PortableRoot $installRoot
& (Join-Path $toolsRoot "Create-DesktopShortcut.ps1") -PortableRoot $installRoot -ShortcutPath (Join-Path ([Environment]::GetFolderPath("Desktop")) "NitroSense.lnk")
& (Join-Path $toolsRoot "Install-NitroLauncherStub.ps1") -TargetExe (Join-Path $installRoot "NitroSense.exe")
& (Join-Path $toolsRoot "Tidy-NitroConfig.ps1")

Write-Host ""
Write-Host "Installed NitroSense to $installRoot"
