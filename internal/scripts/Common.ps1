Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Require-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator rights are required for this script."
    }
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Reset-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Stop-ProcessesFromPathPrefix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathPrefix
    )

    $normalizedPrefix = [System.IO.Path]::GetFullPath($PathPrefix)
    $stopped = @()

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $processPath = $null
        try {
            $processPath = $_.Path
        } catch {
            $processPath = $null
        }

        if (-not $processPath) {
            return
        }

        $fullProcessPath = [System.IO.Path]::GetFullPath($processPath)
        if ($fullProcessPath.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            try {
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                $stopped += [PSCustomObject]@{
                    ProcessName = $_.ProcessName
                    Id = $_.Id
                    Path = $fullProcessPath
                }
            } catch {
            }
        }
    }

    return $stopped
}

function Normalize-PercentEncodedNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return
    }

    Get-ChildItem -LiteralPath $RootPath -Recurse -Force |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if ($_.Name -notmatch '%[0-9A-Fa-f]{2}') {
                return
            }

            $decodedName = [System.Uri]::UnescapeDataString($_.Name)
            if ($decodedName -eq $_.Name) {
                return
            }

            if ($_.PSIsContainer) {
                $parentPath = $_.Parent.FullName
            } else {
                $parentPath = $_.DirectoryName
            }
            $destinationPath = Join-Path $parentPath $decodedName
            if (-not (Test-Path -LiteralPath $destinationPath)) {
                Move-Item -LiteralPath $_.FullName -Destination $destinationPath
            }
        }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Ensure-Directory -Path $Destination
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Get-MainUwpAppxPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageRoot
    )

    $uwpRoot = Join-Path $PackageRoot "UWP"
    if (-not (Test-Path -LiteralPath $uwpRoot)) {
        throw "UWP folder not found under $PackageRoot"
    }

    $appx = Get-ChildItem -LiteralPath $uwpRoot -Filter "*.appx" -File |
        Where-Object { $_.Name -notmatch '^Microsoft\.' } |
        Sort-Object Length -Descending |
        Select-Object -First 1

    if (-not $appx) {
        throw "Could not find the main NitroSense .appx in $uwpRoot"
    }

    return $appx.FullName
}

function Expand-AppxToFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppxPath,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Reset-Directory -Path $Destination
    & tar.exe -xf $AppxPath -C $Destination
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract $AppxPath with tar.exe"
    }
}

function Get-PackageRootFromExpandedZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpandedRoot
    )

    $candidates = @(Get-ChildItem -LiteralPath $ExpandedRoot -Directory -Recurse | Where-Object {
        (Test-Path (Join-Path $_.FullName "UWP")) -and
        (Test-Path (Join-Path $_.FullName "AgentService")) -and
        (Test-Path (Join-Path $_.FullName "AcerSystemMonitorService"))
    } | Select-Object -ExpandProperty FullName)

    if ((Test-Path (Join-Path $ExpandedRoot "UWP")) -and
        (Test-Path (Join-Path $ExpandedRoot "AgentService")) -and
        (Test-Path (Join-Path $ExpandedRoot "AcerSystemMonitorService"))) {
        return $ExpandedRoot
    }

    if ($candidates.Count -eq 0) {
        throw "Could not find the NitroSense package root inside $ExpandedRoot"
    }

    return ($candidates | Select-Object -First 1)
}

function Extract-AsarArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AsarPath,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Reset-Directory -Path $Destination

    $bytes = [System.IO.File]::ReadAllBytes($AsarPath)
    if ($bytes.Length -lt 16) {
        throw "ASAR file is too small: $AsarPath"
    }

    $headerLength = [BitConverter]::ToUInt32($bytes, 12)
    $headerOffset = 16
    $contentOffset = $headerOffset + $headerLength
    $json = [System.Text.Encoding]::UTF8.GetString($bytes, $headerOffset, $headerLength)
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $header = $serializer.DeserializeObject($json)

    function Expand-AsarNode {
        param(
            [Parameter(Mandatory = $true)]
            $Node,
            [Parameter(Mandatory = $true)]
            [string]$CurrentPath
        )

        foreach ($entry in $Node.GetEnumerator()) {
            $name = [string]$entry.Key
            $value = $entry.Value
            $targetPath = Join-Path $CurrentPath $name

            if ($value.ContainsKey("files")) {
                Ensure-Directory -Path $targetPath
                Expand-AsarNode -Node $value["files"] -CurrentPath $targetPath
                continue
            }

            if (-not $value.ContainsKey("size") -or -not $value.ContainsKey("offset")) {
                continue
            }

            $size = [int64]$value["size"]
            $offset = [int64]$value["offset"]
            $absoluteOffset = $contentOffset + $offset
            Ensure-Directory -Path (Split-Path -Parent $targetPath)
            $stream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            try {
                $stream.Write($bytes, $absoluteOffset, $size)
            } finally {
                $stream.Dispose()
            }

            if ($value.ContainsKey("executable") -and $value["executable"]) {
                try {
                    $item = Get-Item -LiteralPath $targetPath -Force
                    $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Archive
                } catch {
                }
            }
        }
    }

    Expand-AsarNode -Node $header.files -CurrentPath $Destination
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    Ensure-Directory -Path (Split-Path -Parent $Path)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Backup-FileOnce {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Suffix
    )

    $backupPath = "$Path$Suffix"
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    }

    return $backupPath
}

function Ensure-ServiceBinary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$BinaryPath
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        New-Service -Name $Name -BinaryPathName $BinaryPath -DisplayName $DisplayName -StartupType Automatic | Out-Null
    } else {
        & sc.exe config $Name binPath= "`"$BinaryPath`"" start= auto | Out-Null
    }

    & sc.exe description $Name $Description | Out-Null
    Set-Service -Name $Name -StartupType Automatic
}

function Start-ServiceIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Running") {
        Start-Service -Name $Name
    }
}

function Invoke-PnpUtilInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InfPath
    )

    Write-Host "Installing $InfPath"
    $output = & pnputil.exe /add-driver $InfPath /install 2>&1
    $exitCode = $LASTEXITCODE

    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }

    $outputText = ($output | Out-String)
    $isAcceptedIdempotentResult =
        ($outputText -match 'Driver package added successfully') -or
        ($outputText -match 'already exists in the system') -or
        ($outputText -match 'Driver package is up-to-date on device')

    if ($exitCode -ne 0 -and -not $isAcceptedIdempotentResult) {
        throw "pnputil failed for $InfPath (exit code $exitCode)"
    }
}
