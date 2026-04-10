[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:ProgramFiles\NitroSense",
    [string]$TaskName = "NitroSenseFanController",
    [switch]$RemoveConfig
)

. (Join-Path $PSScriptRoot "Common.ps1")

Require-Administrator

$installRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$controllerRoot = Join-Path $installRoot "FanController"
$programDataRoot = Join-Path $env:ProgramData "NitroSense\FanController"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -like "*Run-BackgroundFanController.ps1*"
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

if (Test-Path -LiteralPath $controllerRoot) {
    Remove-Item -LiteralPath $controllerRoot -Recurse -Force
}

if ($RemoveConfig -and (Test-Path -LiteralPath $programDataRoot)) {
    Remove-Item -LiteralPath $programDataRoot -Recurse -Force
}

Write-Host "Uninstalled background fan controller."
