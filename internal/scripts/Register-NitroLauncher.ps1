[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PortableRoot
)

. (Join-Path $PSScriptRoot "Common.ps1")

$portableRoot = [System.IO.Path]::GetFullPath($PortableRoot)
$exePath = Join-Path $portableRoot "NitroSense.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "NitroSense.exe not found under $PortableRoot"
}

$taskName = "NitroSenseLauncher"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $exePath -Argument "xsense:gotoPage=MainPage"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 72)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

Write-Host "NitroSenseLauncher task created for $currentUser."
