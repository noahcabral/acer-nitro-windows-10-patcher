[CmdletBinding()]
param(
    [string]$ConfigPath = "C:\ProgramData\OEM\NitroSense\ProfilePool\config.json"
)

. (Join-Path $PSScriptRoot "Common.ps1")

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Warning "Config file not found yet: $ConfigPath"
    return
}

Backup-FileOnce -Path $ConfigPath -Suffix ".win10-byoi-backup" | Out-Null

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

if ($config.PSObject.Properties.Name -contains "WidgetsList" -and $config.WidgetsList) {
    $filtered = @($config.WidgetsList | Where-Object { $_ -ne "App_Shortcut" -and $_ -ne "Live_Update" })
    $config.WidgetsList = $filtered
}

$json = $config | ConvertTo-Json -Depth 100
Write-Utf8NoBomFile -Path $ConfigPath -Content $json

Write-Host "Updated NitroSense profile config."
