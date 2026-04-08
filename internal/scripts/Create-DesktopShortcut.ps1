[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PortableRoot,
    [string]$ShortcutPath = (Join-Path ([Environment]::GetFolderPath("Desktop")) "NitroSense Win10 Portable.lnk")
)

$exePath = Join-Path $PortableRoot "NitroSense.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "NitroSense.exe not found under $PortableRoot"
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $exePath
$shortcut.WorkingDirectory = $PortableRoot
$shortcut.IconLocation = "$exePath,0"
$shortcut.Save()

Write-Host "Shortcut created: $ShortcutPath"
