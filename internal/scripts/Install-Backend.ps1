[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot,
    [string]$WorkRoot = (Join-Path (Get-Location) "internal\build\backend-work")
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

function Invoke-PatchedExtensionInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InfPath,
        [Parameter(Mandatory = $true)]
        [string]$OriginalInfName,
        [Parameter(Mandatory = $true)]
        [string]$FriendlyName
    )

    if (Test-DriverOriginalNamePresent -OriginalInfName $OriginalInfName) {
        Write-Host "Skipping $FriendlyName because $OriginalInfName is already present in the driver store."
        return
    }

    try {
        Invoke-PnpUtilInstall -InfPath $InfPath
    } catch {
        $message = $_.Exception.Message
        if ($message -match 'exit code -536870353') {
            throw "$FriendlyName needs the patched unsigned INF, but Windows rejected it under normal driver signature enforcement. Reboot once with 'Disable driver signature enforcement' and rerun install.bat."
        }

        throw
    }
}

function Stop-ServiceIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Stopped") {
        Stop-Service -Name $Name -Force -ErrorAction Stop
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
    }
}

function Patch-SysMonitorExtensionInf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $content = Get-Content -LiteralPath $SourcePath -Raw
    $content = $content.Replace(
        "%ManufacturerString%=AcerInc,NTarm64.10.0...15063,NTamd64.10.0...15063,NTarm64.10.0...22631,NTamd64.10.0...22631",
        "%ManufacturerString%=AcerInc,NTarm64.10.0...15063,NTamd64.10.0...15063,NTamd64.10.0...19041,NTarm64.10.0...22631,NTamd64.10.0...22631"
    )

    $pattern = '(?s)(\[AcerInc\.NTamd64\.10\.0\.\.\.22631\].*?)(?=\r?\n\[AcerInc\.NTarm64\.10\.0\.\.\.22631\])'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) {
        throw "Could not find the Win11 AMD64 section in SysMonitorServiceExtension.inf"
    }

    $section19041 = $match.Groups[1].Value.Replace("[AcerInc.NTamd64.10.0...22631]", "[AcerInc.NTamd64.10.0...19041]")
    $content = [regex]::Replace($content, $pattern, ($section19041 + "`r`n`r`n" + $match.Groups[1].Value), 1)

    Write-Utf8NoBomFile -Path $DestinationPath -Content $content
}

function Patch-SimpleExtensionInf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter(Mandatory = $true)]
        [string]$ManufacturerLine,
        [Parameter(Mandatory = $true)]
        [string]$UpdatedManufacturerLine,
        [Parameter(Mandatory = $true)]
        [string]$Section22000,
        [Parameter(Mandatory = $true)]
        [string]$Section19041
    )

    $content = Get-Content -LiteralPath $SourcePath -Raw
    $content = $content.Replace($ManufacturerLine, $UpdatedManufacturerLine)

    $pattern = '(?s)(' + [regex]::Escape($Section22000) + '.*?)(?=\r?\n\[.+?\]|\Z)'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) {
        throw "Could not find $Section22000 in $SourcePath"
    }

    $section19041Body = $match.Groups[1].Value.Replace($Section22000, $Section19041)
    $content = [regex]::Replace($content, $pattern, ($section19041Body + "`r`n`r`n" + $match.Groups[1].Value), 1)

    Write-Utf8NoBomFile -Path $DestinationPath -Content $content
}

$patchedRoot = Join-Path $WorkRoot "patched-inf"
Reset-Directory -Path $patchedRoot

$sysMonPatched = Join-Path $patchedRoot "SysMonitorServiceExtension.inf"
$qaExtPatched = Join-Path $patchedRoot "acerqa_ext.inf"
$ccExtPatched = Join-Path $patchedRoot "acercc_ext.inf"

Patch-SysMonitorExtensionInf `
    -SourcePath (Join-Path $PackageRoot "AcerSystemMonitorService\SysMonitorServiceExtension.inf") `
    -DestinationPath $sysMonPatched

Patch-SimpleExtensionInf `
    -SourcePath (Join-Path $PackageRoot "AcerQAAgent\acerqa_ext.inf") `
    -DestinationPath $qaExtPatched `
    -ManufacturerLine "%ManufacturerName% = AQAExtension, NTamd64.10.0...22000" `
    -UpdatedManufacturerLine "%ManufacturerName% = AQAExtension, NTamd64.10.0...19041, NTamd64.10.0...22000" `
    -Section22000 "[AQAExtension.NTamd64.10.0...22000]" `
    -Section19041 "[AQAExtension.NTamd64.10.0...19041]"

Patch-SimpleExtensionInf `
    -SourcePath (Join-Path $PackageRoot "AcerCCAgent\acercc_ext.inf") `
    -DestinationPath $ccExtPatched `
    -ManufacturerLine "%ManufacturerName% = ACCExtension, NTamd64.10.0...22000" `
    -UpdatedManufacturerLine "%ManufacturerName% = ACCExtension, NTamd64.10.0...19041, NTamd64.10.0...22000" `
    -Section22000 "[ACCExtension.NTamd64.10.0...22000]" `
    -Section19041 "[ACCExtension.NTamd64.10.0...19041]"

Invoke-PnpUtilInstall -InfPath (Join-Path $PackageRoot "AgentService\driver\PredatorServiceExtension.inf")
Invoke-PnpUtilInstall -InfPath (Join-Path $PackageRoot "AgentService\driver\PredatorService.inf")
Invoke-PatchedExtensionInstall -InfPath $sysMonPatched -OriginalInfName "sysmonitorserviceextension.inf" -FriendlyName "Acer System Monitor Service Extension"
Invoke-PnpUtilInstall -InfPath (Join-Path $PackageRoot "AcerSystemMonitorService\SysMonitorService.inf")
Invoke-PatchedExtensionInstall -InfPath $qaExtPatched -OriginalInfName "acerqa_ext.inf" -FriendlyName "Acer Quick Access Extension"
Invoke-PatchedExtensionInstall -InfPath $ccExtPatched -OriginalInfName "acercc_ext.inf" -FriendlyName "Acer Care Center Extension"

$qaTarget = Join-Path ${env:ProgramFiles} "AcerQAAgent"
$ccTarget = Join-Path ${env:ProgramFiles} "AcerCCAgent"

Stop-ServiceIfPresent -Name "AcerQAAgentSvis"
Stop-ServiceIfPresent -Name "AcerCCAgentSvis"

$null = Stop-ProcessesFromPathPrefix -PathPrefix $qaTarget
$null = Stop-ProcessesFromPathPrefix -PathPrefix $ccTarget

Copy-DirectoryContents -Source (Join-Path $PackageRoot "AcerQAAgent") -Destination $qaTarget
Copy-DirectoryContents -Source (Join-Path $PackageRoot "AcerCCAgent") -Destination $ccTarget

Ensure-ServiceBinary `
    -Name "AcerQAAgentSvis" `
    -DisplayName "Acer Quick Access" `
    -Description "Acer Quick Access Service" `
    -BinaryPath (Join-Path $qaTarget "AcerQAAgent.exe")

Ensure-ServiceBinary `
    -Name "AcerCCAgentSvis" `
    -DisplayName "Acer Care Center" `
    -Description "Acer Care Center Service" `
    -BinaryPath (Join-Path $ccTarget "AcerCCAgent.exe")

Start-ServiceIfNeeded -Name "AcerQAAgentSvis"
Start-ServiceIfNeeded -Name "AcerCCAgentSvis"
Start-ServiceIfNeeded -Name "AASSvc"
Start-ServiceIfNeeded -Name "ASMSvc"
Start-ServiceIfNeeded -Name "AcerLightingService"

Write-Host "Backend install finished."
Write-Host "If the patched INF installs fail, reboot once with driver signature enforcement disabled and rerun this script."
