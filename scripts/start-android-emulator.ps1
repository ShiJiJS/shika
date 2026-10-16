[CmdletBinding()]
param(
    [string]$AvdName = 'video_viewer_api_36',
    [int]$Port = 5554,
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'

$sdkDirectory = $env:ANDROID_HOME
if (-not $sdkDirectory) {
    $sdkDirectory = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User')
}
if (-not $sdkDirectory) {
    $sdkDirectory = Join-Path $env:USERPROFILE 'develop\android-sdk'
}

$adbCommand = Join-Path $sdkDirectory 'platform-tools\adb.exe'
$emulatorCommand = Join-Path $sdkDirectory 'emulator\emulator.exe'
if (-not (Test-Path -LiteralPath $adbCommand) -or -not (Test-Path -LiteralPath $emulatorCommand)) {
    throw 'Android platform-tools and emulator must be installed first.'
}

$availableAvds = @(& $emulatorCommand -list-avds)
if ($availableAvds -notcontains $AvdName) {
    throw "AVD '$AvdName' does not exist. See the Android development setup document."
}

$deviceId = "emulator-$Port"
$deviceList = @(& $adbCommand devices)
$existingDevice = $deviceList | Where-Object { $_ -match "^$([regex]::Escape($deviceId))\s" }
if (-not $existingDevice) {
    $logDirectory = Join-Path $env:LOCALAPPDATA 'video-viewer\dev-logs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $logStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Start-Process -FilePath $emulatorCommand `
        -ArgumentList @(
            '-avd', $AvdName, '-port', "$Port", '-no-boot-anim',
            '-gpu', 'software', '-feature', '-Vulkan', '-no-snapshot'
        ) `
        -WindowStyle Normal `
        -RedirectStandardOutput (Join-Path $logDirectory "emulator-$logStamp.stdout.log") `
        -RedirectStandardError (Join-Path $logDirectory "emulator-$logStamp.stderr.log") | Out-Null
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    $connectedDevices = @(& $adbCommand devices)
    $readyDevice = $connectedDevices | Where-Object { $_ -match "^$([regex]::Escape($deviceId))\s+device$" }
    if ($readyDevice) {
        $runningName = @(& $adbCommand -s $deviceId emu avd name)[0]
        if (-not $runningName -or $runningName.Trim() -ne $AvdName) {
            throw "Port $Port belongs to another emulator. Close it or select another port explicitly."
        }
        $bootComplete = @(& $adbCommand -s $deviceId shell getprop sys.boot_completed)
        if ($LASTEXITCODE -eq 0 -and ($bootComplete -join '').Trim() -eq '1') {
            Write-Output "$AvdName is ready on $deviceId."
            exit 0
        }
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

throw "Emulator $deviceId did not finish booting within $TimeoutSeconds seconds."
