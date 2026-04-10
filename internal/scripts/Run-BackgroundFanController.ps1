[CmdletBinding()]
param(
    [string]$ConfigPath = "$env:ProgramData\NitroSense\FanController\config.json",
    [string]$LogPath = "$env:ProgramData\NitroSense\FanController\controller.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    Ensure-Directory -Path (Split-Path -Parent $Path)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Write-ControllerLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")][string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f ([DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")), $Level, $Message
    Add-Content -LiteralPath $script:ResolvedLogPath -Value $line -Encoding UTF8
}

function Get-DefaultCurve {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("cpu", "gpu")]
        [string]$FanName
    )

    if ($FanName -eq "cpu") {
        return @(
            @{ temp = 40; speed = 25 },
            @{ temp = 55; speed = 35 },
            @{ temp = 65; speed = 50 },
            @{ temp = 75; speed = 70 },
            @{ temp = 85; speed = 100 }
        )
    }

    return @(
        @{ temp = 35; speed = 25 },
        @{ temp = 50; speed = 35 },
        @{ temp = 60; speed = 50 },
        @{ temp = 70; speed = 75 },
        @{ temp = 80; speed = 100 }
    )
}

function New-DefaultScenarioConfig {
    return [ordered]@{
        enabled = $true
        cpuCurve = @(Get-DefaultCurve -FanName "cpu")
        gpuCurve = @(Get-DefaultCurve -FanName "gpu")
    }
}

function Get-DefaultControllerConfig {
    return [ordered]@{
        enabled = $true
        pollIntervalMs = 3000
        applyDeltaPercent = 3
        acOnly = $false
        followNitroScenario = $true
        nitroConfigPath = "C:\ProgramData\OEM\NitroSense\ProfilePool\config.json"
        defaultScenario = New-DefaultScenarioConfig
        scenarios = [ordered]@{}
    }
}

function Ensure-ControllerConfig {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        $json = (Get-DefaultControllerConfig | ConvertTo-Json -Depth 8)
        Write-Utf8NoBomFile -Path $Path -Content $json
    }
}

function ConvertTo-NormalizedCurve {
    param(
        $Curve,
        [Parameter(Mandatory = $true)]
        [ValidateSet("cpu", "gpu")]
        [string]$FanName
    )

    $defaultCurve = @(Get-DefaultCurve -FanName $FanName)
    if ($null -eq $Curve) {
        return $defaultCurve
    }

    $normalized = @()
    foreach ($point in @($Curve)) {
        if ($null -eq $point) {
            continue
        }

        $temp = $null
        $speed = $null
        if ($point.PSObject -and $point.PSObject.Properties.Name -contains "temp") {
            $temp = [int]$point.temp
        }
        if ($point.PSObject -and $point.PSObject.Properties.Name -contains "speed") {
            $speed = [int]$point.speed
        }

        if ($null -eq $temp -or $null -eq $speed) {
            continue
        }

        $normalized += [ordered]@{
            temp = $temp
            speed = $speed
        }
    }

    if ($normalized.Count -lt 2) {
        return $defaultCurve
    }

    return @($normalized | Sort-Object temp)
}

function ConvertTo-NormalizedScenarioConfig {
    param($ScenarioConfig)

    if ($null -eq $ScenarioConfig) {
        return (New-DefaultScenarioConfig)
    }

    return [ordered]@{
        enabled = if ($ScenarioConfig.PSObject -and $ScenarioConfig.PSObject.Properties.Name -contains "enabled") { [bool]$ScenarioConfig.enabled } else { $true }
        cpuCurve = ConvertTo-NormalizedCurve -Curve $ScenarioConfig.cpuCurve -FanName "cpu"
        gpuCurve = ConvertTo-NormalizedCurve -Curve $ScenarioConfig.gpuCurve -FanName "gpu"
    }
}

function Get-ControllerConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $parsed = $raw | ConvertFrom-Json
    $config = Get-DefaultControllerConfig

    if ($null -ne $parsed) {
        if ($parsed.PSObject.Properties.Name -contains "enabled") {
            $config.enabled = [bool]$parsed.enabled
        }
        if ($parsed.PSObject.Properties.Name -contains "pollIntervalMs") {
            $config.pollIntervalMs = [int]$parsed.pollIntervalMs
        }
        if ($parsed.PSObject.Properties.Name -contains "applyDeltaPercent") {
            $config.applyDeltaPercent = [int]$parsed.applyDeltaPercent
        }
        if ($parsed.PSObject.Properties.Name -contains "acOnly") {
            $config.acOnly = [bool]$parsed.acOnly
        }
        if ($parsed.PSObject.Properties.Name -contains "followNitroScenario") {
            $config.followNitroScenario = [bool]$parsed.followNitroScenario
        }
        if ($parsed.PSObject.Properties.Name -contains "nitroConfigPath" -and [string]::IsNullOrWhiteSpace([string]$parsed.nitroConfigPath) -eq $false) {
            $config.nitroConfigPath = [string]$parsed.nitroConfigPath
        }

        if (($parsed.PSObject.Properties.Name -contains "cpuCurve") -or ($parsed.PSObject.Properties.Name -contains "gpuCurve")) {
            $config.defaultScenario = [ordered]@{
                enabled = $true
                cpuCurve = ConvertTo-NormalizedCurve -Curve $parsed.cpuCurve -FanName "cpu"
                gpuCurve = ConvertTo-NormalizedCurve -Curve $parsed.gpuCurve -FanName "gpu"
            }
        }

        if ($parsed.PSObject.Properties.Name -contains "defaultScenario") {
            $config.defaultScenario = ConvertTo-NormalizedScenarioConfig -ScenarioConfig $parsed.defaultScenario
        }

        if ($parsed.PSObject.Properties.Name -contains "scenarios" -and $parsed.scenarios) {
            $scenarioTable = [ordered]@{}
            foreach ($property in $parsed.scenarios.PSObject.Properties) {
                $scenarioTable[$property.Name] = ConvertTo-NormalizedScenarioConfig -ScenarioConfig $property.Value
            }
            $config.scenarios = $scenarioTable
        }
    }

    return $config
}

function ConvertTo-AcerPacketBytes {
    param(
        [Parameter(Mandatory = $true)][UInt32]$PacketId,
        [Parameter(Mandatory = $true)]$Payload
    )

    $json = [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 10))
    $bytes = New-Object byte[] (8 + $json.Length)
    [System.Text.Encoding]::ASCII.GetBytes("ACER").CopyTo($bytes, 0)
    [BitConverter]::GetBytes($PacketId).CopyTo($bytes, 4)
    $json.CopyTo($bytes, 8)
    return $bytes
}

function Invoke-AcerSocketRequest {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][UInt32]$PacketId,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$TimeoutMs = 5000
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            throw "Timed out connecting to 127.0.0.1:$Port"
        }
        $client.EndConnect($async)
        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = $TimeoutMs

        $stream = $client.GetStream()
        $requestBytes = ConvertTo-AcerPacketBytes -PacketId $PacketId -Payload $Payload
        $stream.Write($requestBytes, 0, $requestBytes.Length)
        $stream.Flush()

        $builder = New-Object System.Text.StringBuilder
        $buffer = New-Object byte[] 4096
        $depth = 0
        $started = $false

        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                break
            }

            $chunk = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
            foreach ($char in $chunk.ToCharArray()) {
                if ($char -eq '{') {
                    $started = $true
                    $depth++
                }

                if ($started) {
                    [void]$builder.Append($char)
                }

                if ($char -eq '}') {
                    $depth--
                    if ($started -and $depth -eq 0) {
                        $json = $builder.ToString()
                        return ($json | ConvertFrom-Json)
                    }
                }
            }
        }

        throw "No JSON response received from 127.0.0.1:$Port"
    } finally {
        if ($client.Connected) {
            $client.Close()
        } else {
            $client.Dispose()
        }
    }
}

function Get-AcerFanSupport {
    return (Invoke-AcerSocketRequest -Port 46933 -PacketId 0 -Payload @{ Function = "SUPPORT_FAN_CONTROL" }).data
}

function Get-AcerMonitorData {
    return (Invoke-AcerSocketRequest -Port 46753 -PacketId 10 -Payload @{}).data
}

function Get-AcerAdaptorStatus {
    $response = Invoke-AcerSocketRequest -Port 46933 -PacketId 20 -Payload @{ Function = "ADAPTOR_STATUS" }
    return [int]$response.data.status
}

function Set-AcerFanControl {
    param([Parameter(Mandatory = $true)]$Payload)
    return (Invoke-AcerSocketRequest -Port 46933 -PacketId 100 -Payload @{
        Function = "FAN_CONTROL"
        Parameter = $Payload
    })
}

function Get-InterpolatedFanSpeed {
    param(
        [Parameter(Mandatory = $true)][double]$Temperature,
        [Parameter(Mandatory = $true)]$Curve
    )

    $points = @($Curve | Sort-Object temp)
    if ($points.Count -eq 0) {
        return 30
    }

    if ($Temperature -le [double]$points[0].temp) {
        return [int][math]::Round([double]$points[0].speed)
    }

    for ($i = 1; $i -lt $points.Count; $i++) {
        $left = $points[$i - 1]
        $right = $points[$i]
        $leftTemp = [double]$left.temp
        $rightTemp = [double]$right.temp

        if ($Temperature -le $rightTemp) {
            $span = $rightTemp - $leftTemp
            if ($span -le 0) {
                return [int][math]::Round([double]$right.speed)
            }

            $ratio = ($Temperature - $leftTemp) / $span
            $speed = [double]$left.speed + ((([double]$right.speed) - ([double]$left.speed)) * $ratio)
            return [int][math]::Round($speed)
        }
    }

    return [int][math]::Round([double]$points[$points.Count - 1].speed)
}

function Limit-Percent {
    param([int]$Value, [int]$MinValue = 0, [int]$MaxValue = 100)
    if ($Value -lt $MinValue) { return $MinValue }
    if ($Value -gt $MaxValue) { return $MaxValue }
    return $Value
}

function Get-GpuTemperature {
    param([Parameter(Mandatory = $true)]$MonitorData)

    $gpuTemp = 0
    if ($null -ne $MonitorData.PSObject.Properties["GPU1_TEMPERATURE"]) {
        $gpuTemp = [double]$MonitorData.GPU1_TEMPERATURE
    }

    if ($gpuTemp -gt 0) {
        return $gpuTemp
    }

    if ($null -ne $MonitorData.PSObject.Properties["SYS1_TEMPERATURE"]) {
        return [double]$MonitorData.SYS1_TEMPERATURE
    }

    return 0
}

function New-FanControlPayload {
    param(
        [Parameter(Mandatory = $true)]$Support,
        [Parameter(Mandatory = $true)][int]$CpuSpeed,
        [Parameter(Mandatory = $true)][int]$GpuSpeed
    )

    $customFans = @()
    foreach ($fan in $Support) {
        $targetSpeed = if ($fan.fan_name -like "CPU*") { $CpuSpeed } else { $GpuSpeed }
        $customFans += [ordered]@{
            fan_custom_auto = 0
            fan_custom_speed = $targetSpeed
            fan_index = [int]$fan.fan_index
            fan_name = [string]$fan.fan_name
        }
    }

    return [ordered]@{
        mode = 2
        custom_fan_data = $customFans
    }
}

function Get-TargetSpeeds {
    param(
        [Parameter(Mandatory = $true)]$ScenarioConfig,
        [Parameter(Mandatory = $true)]$MonitorData
    )

    $cpuTemp = [double]$MonitorData.CPU_TEMPERATURE
    $gpuTemp = Get-GpuTemperature -MonitorData $MonitorData

    return [ordered]@{
        CpuTemp = [int][math]::Round($cpuTemp)
        GpuTemp = [int][math]::Round($gpuTemp)
        CpuSpeed = Limit-Percent (Get-InterpolatedFanSpeed -Temperature $cpuTemp -Curve $ScenarioConfig.cpuCurve)
        GpuSpeed = Limit-Percent (Get-InterpolatedFanSpeed -Temperature $gpuTemp -Curve $ScenarioConfig.gpuCurve)
    }
}

function Test-ShouldApply {
    param(
        $LastApplied,
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][int]$ApplyDeltaPercent
    )

    if ($null -eq $LastApplied) {
        return $true
    }

    return (
        [math]::Abs($LastApplied.CpuSpeed - $Target.CpuSpeed) -ge $ApplyDeltaPercent -or
        [math]::Abs($LastApplied.GpuSpeed - $Target.GpuSpeed) -ge $ApplyDeltaPercent
    )
}

function Get-ActiveNitroScenarioState {
    param([Parameter(Mandatory = $true)][string]$NitroConfigPath)

    $state = [ordered]@{
        Name = "Default"
        FanMode = 2
    }

    if (-not (Test-Path -LiteralPath $NitroConfigPath)) {
        return $state
    }

    try {
        $nitroConfig = Get-Content -LiteralPath $NitroConfigPath -Raw | ConvertFrom-Json
        if ($null -eq $nitroConfig -or $null -eq $nitroConfig.Scenario) {
            return $state
        }

        $profiles = @($nitroConfig.Scenario.profiles)
        if ($profiles.Count -eq 0) {
            return $state
        }

        $activeIndex = 0
        if ($nitroConfig.Scenario.PSObject.Properties.Name -contains "active") {
            $activeIndex = [int]$nitroConfig.Scenario.active
        } elseif ($nitroConfig.Scenario.PSObject.Properties.Name -contains "select") {
            $activeIndex = [int]$nitroConfig.Scenario.select
        }

        if ($activeIndex -lt 0 -or $activeIndex -ge $profiles.Count) {
            $activeIndex = 0
        }

        $profile = $profiles[$activeIndex]
        if ($profile.PSObject.Properties.Name -contains "name" -and [string]::IsNullOrWhiteSpace([string]$profile.name) -eq $false) {
            $state.Name = [string]$profile.name
        }
        if ($profile.PSObject.Properties.Name -contains "fanControl" -and $profile.fanControl -and $profile.fanControl.PSObject.Properties.Name -contains "mode") {
            $state.FanMode = [int]$profile.fanControl.mode
        }
    } catch {
        Write-ControllerLog -Message ("Failed to read NitroSense scenario config: {0}" -f $_.Exception.Message) -Level "WARN"
    }

    return $state
}

function Get-EffectiveScenarioConfig {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ScenarioName
    )

    if ($Config.scenarios -and $Config.scenarios.Contains($ScenarioName)) {
        return (ConvertTo-NormalizedScenarioConfig -ScenarioConfig $Config.scenarios[$ScenarioName])
    }

    return (ConvertTo-NormalizedScenarioConfig -ScenarioConfig $Config.defaultScenario)
}

$script:ResolvedConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
$script:ResolvedLogPath = [System.IO.Path]::GetFullPath($LogPath)

Ensure-Directory -Path (Split-Path -Parent $script:ResolvedConfigPath)
Ensure-Directory -Path (Split-Path -Parent $script:ResolvedLogPath)
Ensure-ControllerConfig -Path $script:ResolvedConfigPath

$mutexName = "Local\NitroSenseBackgroundFanController"
$mutex = [System.Threading.Mutex]::new($false, $mutexName)
$hasMutex = $false

try {
    $hasMutex = $mutex.WaitOne(0)
    if (-not $hasMutex) {
        Write-ControllerLog -Message "Another fan controller instance is already running." -Level "WARN"
        exit 0
    }

    $support = Get-AcerFanSupport
    Write-ControllerLog -Message ("Controller started. Supported fans: {0}" -f (($support | ForEach-Object { $_.fan_name }) -join ", "))

    $lastApplied = $null
    $lastScenarioName = $null

    while ($true) {
        try {
            $config = Get-ControllerConfig -Path $script:ResolvedConfigPath
            $pollIntervalMs = [math]::Max([int]$config.pollIntervalMs, 1000)
            $applyDeltaPercent = [math]::Max([int]$config.applyDeltaPercent, 1)

            if (-not [bool]$config.enabled) {
                $lastApplied = $null
                Start-Sleep -Milliseconds $pollIntervalMs
                continue
            }

            if ([bool]$config.acOnly) {
                $adaptorStatus = Get-AcerAdaptorStatus
                if ($adaptorStatus -eq 0) {
                    $lastApplied = $null
                    Start-Sleep -Milliseconds $pollIntervalMs
                    continue
                }
            }

            $scenarioState = Get-ActiveNitroScenarioState -NitroConfigPath $config.nitroConfigPath
            if ($scenarioState.Name -ne $lastScenarioName) {
                $lastApplied = $null
                $lastScenarioName = $scenarioState.Name
            }

            if ([bool]$config.followNitroScenario -and $scenarioState.FanMode -ne 2) {
                $lastApplied = $null
                Start-Sleep -Milliseconds $pollIntervalMs
                continue
            }

            $scenarioConfig = Get-EffectiveScenarioConfig -Config $config -ScenarioName $scenarioState.Name
            if (-not [bool]$scenarioConfig.enabled) {
                $lastApplied = $null
                Start-Sleep -Milliseconds $pollIntervalMs
                continue
            }

            $monitor = Get-AcerMonitorData
            $target = Get-TargetSpeeds -ScenarioConfig $scenarioConfig -MonitorData $monitor

            if (Test-ShouldApply -LastApplied $lastApplied -Target $target -ApplyDeltaPercent $applyDeltaPercent) {
                $payload = New-FanControlPayload -Support $support -CpuSpeed $target.CpuSpeed -GpuSpeed $target.GpuSpeed
                [void](Set-AcerFanControl -Payload $payload)
                Write-ControllerLog -Message ("Applied fan curve [{0}] CPU {1}C->{2}% GPU {3}C->{4}%" -f $scenarioState.Name, $target.CpuTemp, $target.CpuSpeed, $target.GpuTemp, $target.GpuSpeed)
                $lastApplied = $target
            }

            Start-Sleep -Milliseconds $pollIntervalMs
        } catch {
            Write-ControllerLog -Message ("Loop error: {0}" -f $_.Exception.Message) -Level "ERROR"
            Start-Sleep -Seconds 5
        }
    }
} finally {
    if ($hasMutex) {
        [void]$mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
