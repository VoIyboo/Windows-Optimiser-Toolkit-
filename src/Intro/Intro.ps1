# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit (Progress + Swap to Main UI)

param(
    [switch]$SkipSplash,
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# -------------------------------------------------
# Log file path (always exists)
# -------------------------------------------------
if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogPath = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}
$script:QOTLogPath = $LogPath

# -------------------------------------------------
# Fallback logging (SCRIPT SCOPE, ALWAYS AVAILABLE)
# -------------------------------------------------
function script:Write-QLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"

    try { $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8 } catch { }
    if (-not $Quiet) { Write-Host $line }
}

function script:Set-QLogRoot {
    param([Parameter(Mandatory)][string]$Root)

    $script:QLogRoot = $Root
    if (-not (Test-Path $script:QLogRoot)) {
        New-Item -ItemType Directory -Path $script:QLogRoot -Force | Out-Null
    }
}

function script:Start-QLogSession {
    param([string]$Prefix = "QuinnOptimiserToolkit")
    Write-QLog "Log session started." "INFO"
}

# -------------------------------------------------
# Silence noisy warnings
# -------------------------------------------------
$oldWarningPreference = $WarningPreference
$WarningPreference = 'SilentlyContinue'

try {
    # -------------------------------------------------
    # WPF assemblies
    # -------------------------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # -------------------------------------------------
    # Resolve root + modules
    # -------------------------------------------------
    $rootPath     = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModule = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    # -------------------------------------------------
    # Paths used by SplashHost
    # -------------------------------------------------
    $signalPath   = Join-Path $env:TEMP "QOT_ready.signal"
    $progressPath = Join-Path $env:TEMP "QOT_progress.json"

    # Clean old files
    Remove-Item -LiteralPath $signalPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue

    # -------------------------------------------------
    # Import Config (best effort)
    # -------------------------------------------------
    if (Test-Path $configModule) {
        Import-Module $configModule -Force -ErrorAction SilentlyContinue
    }

    # -------------------------------------------------
    # Import real logging (optional override)
    # -------------------------------------------------
    if (Test-Path $loggingModule) {
        try {
            Import-Module $loggingModule -Force -ErrorAction Stop
        } catch { }
    }

    # -------------------------------------------------
    # Engine is REQUIRED
    # -------------------------------------------------
    if (-not (Test-Path $engineModule)) {
        throw "Engine module not found at $engineModule"
    }
    Import-Module $engineModule -Force -ErrorAction Stop

    # -------------------------------------------------
    # Init config + logging
    # -------------------------------------------------
    function Initialize-QOTConfig {
        param([Parameter(Mandatory)][string]$RootPath)

        $Global:QOTRoot = $RootPath

        $programDataRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit"
        $logsRoot        = Join-Path $programDataRoot "Logs"

        foreach ($p in @($programDataRoot, $logsRoot)) {
            if (-not (Test-Path $p)) {
                New-Item -Path $p -ItemType Directory -Force | Out-Null
            }
        }

        [pscustomobject]@{
            Root     = $RootPath
            LogsRoot = $logsRoot
        }
    }

    $cfg = Initialize-QOTConfig -RootPath $rootPath

    Set-QLogRoot -Root $cfg.LogsRoot
    Start-QLogSession
    Write-QLog "Intro starting. Root = $rootPath" "INFO"

    # -------------------------------------------------
    # Background prep work while splash is open
    # -------------------------------------------------
    Start-Job -ArgumentList $rootPath, $progressPath, $signalPath -ScriptBlock {
        param($RootPath, $ProgressPath, $SignalPath)

        function Set-Progress([int]$Percent, [string]$Status) {
            @{ progress = $Percent; status = $Status } |
                ConvertTo-Json |
                Set-Content -LiteralPath $ProgressPath -Encoding UTF8
        }

        try {
            Set-Progress 5  "Starting..."
            Start-Sleep -Milliseconds 200

            Set-Progress 20 "Loading config..."
            Import-Module (Join-Path $RootPath "src\Core\Config\Config.psm1") -Force -ErrorAction Stop

            Set-Progress 40 "Loading logging..."
            Import-Module (Join-Path $RootPath "src\Core\Logging\Logging.psm1") -Force -ErrorAction Stop

            Set-Progress 70 "Loading engine..."
            Import-Module (Join-Path $RootPath "src\Core\Engine\Engine.psm1") -Force -ErrorAction Stop

            Set-Progress 95 "Finalising..."
            Start-Sleep -Milliseconds 400

            Set-Progress 100 "Ready"
            Start-Sleep -Seconds 2

            New-Item -ItemType File -Path $SignalPath -Force | Out-Null
        }
        catch {
            Set-Progress 100 ("Failed: " + $_.Exception.Message)
            Start-Sleep -Seconds 2
            New-Item -ItemType File -Path $SignalPath -Force | Out-Null
        }
    } | Out-Null

        # -------------------------------------------------
        # Fox splash (Splash.xaml)
        # -------------------------------------------------
        $splash = $null
        if (-not $SkipSplash -and (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue)) {
            $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
            $splash = New-QOTSplashWindow -Path $splashXaml
        
            if ($splash) {
                # Force centre
                $splash.WindowStartupLocation = "CenterScreen"
                $splash.Topmost = $true
                $splash.Show()
            }
            
            function Set-FoxSplash {
                param(
                    [int]$Percent,
                    [string]$Text
                )
            
                if (-not $splash) { return }
            
                $splash.Dispatcher.Invoke([action]{
                    $bar = $splash.FindName("SplashProgressBar")
                    $txt = $splash.FindName("SplashStatusText")
            
                    if ($bar) { $bar.Value = [double]$Percent }
                    if ($txt) { $txt.Text = $Text }
                })
            }

              

# -------------------------------------------------
# Loading stages shown on fox splash
# -------------------------------------------------
Set-FoxSplash 5  "Starting Quinn Optimiser Toolkit..."
Start-Sleep -Milliseconds 150

Set-FoxSplash 20 "Loading config..."
if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction SilentlyContinue }

Set-FoxSplash 40 "Loading logging..."
if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction SilentlyContinue }

Set-FoxSplash 65 "Loading engine..."
Import-Module $engineModule -Force -ErrorAction Stop

Set-FoxSplash 85 "Preparing UI..."
Start-Sleep -Milliseconds 200

Set-FoxSplash 100 "Ready"
Start-Sleep -Seconds 2

# -------------------------------------------------
# Swap to main UI
# -------------------------------------------------
Write-QLog "Starting main window" "INFO"
Start-QOTMain -RootPath $rootPath

if ($splash) {
    $splash.Topmost = $false
    $splash.Close()
}

Write-QLog "Intro completed" "INFO"

