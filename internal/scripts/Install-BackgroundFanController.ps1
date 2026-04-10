[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:ProgramFiles\NitroSense",
    [string]$TaskName = "NitroSenseFanController"
)

. (Join-Path $PSScriptRoot "Common.ps1")

Require-Administrator

$installRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$controllerRoot = Join-Path $installRoot "FanController"
$programDataRoot = Join-Path $env:ProgramData "NitroSense\FanController"
$runtimeScriptSource = Join-Path $PSScriptRoot "Run-BackgroundFanController.ps1"
$runtimeScriptTarget = Join-Path $controllerRoot "Run-BackgroundFanController.ps1"
$configPath = Join-Path $programDataRoot "config.json"
$logPath = Join-Path $programDataRoot "controller.log"

if (-not (Test-Path -LiteralPath $runtimeScriptSource)) {
    throw "Background controller script not found: $runtimeScriptSource"
}

Ensure-Directory -Path $controllerRoot
Ensure-Directory -Path $programDataRoot

Copy-Item -LiteralPath $runtimeScriptSource -Destination $runtimeScriptTarget -Force

if (-not (Test-Path -LiteralPath $configPath)) {
    $defaultConfig = @"
{
  "enabled": true,
  "pollIntervalMs": 3000,
  "applyDeltaPercent": 3,
  "acOnly": false,
  "followNitroScenario": true,
  "nitroConfigPath": "C:\\ProgramData\\OEM\\NitroSense\\ProfilePool\\config.json",
  "uiStoragePath": "$($env:APPDATA -replace '\\','\\\\')\\\\acernitrosense\\\\Local Storage\\\\leveldb",
  "defaultScenario": {
    "enabled": true,
    "cpuCurve": [
      { "temp": 40, "speed": 25 },
      { "temp": 55, "speed": 35 },
      { "temp": 65, "speed": 50 },
      { "temp": 75, "speed": 70 },
      { "temp": 85, "speed": 100 }
    ],
    "gpuCurve": [
      { "temp": 35, "speed": 25 },
      { "temp": 50, "speed": 35 },
      { "temp": 60, "speed": 50 },
      { "temp": 70, "speed": 75 },
      { "temp": 80, "speed": 100 }
    ]
  },
  "scenarios": {}
}
"@
    Write-Utf8NoBomFile -Path $configPath -Content $defaultConfig
}

$command = "powershell.exe"
$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runtimeScriptTarget`" -ConfigPath `"$configPath`" -LogPath `"$logPath`""
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction -Execute $command -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -like "*Run-BackgroundFanController.ps1*"
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

Start-ScheduledTask -TaskName $TaskName

Write-Host "Installed background fan controller."
Write-Host "Runtime script: $runtimeScriptTarget"
Write-Host "Config:         $configPath"
Write-Host "Log:            $logPath"
