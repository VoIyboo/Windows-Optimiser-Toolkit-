# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit

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
    $LogPath = Join-Path $logDir ("QOT_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
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
    $rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $signalPath   = Join-Path $env:TEMP "QOT_ready.signal"
    $progressPath = Join-Path $env:TEMP "QOT_progress.json"
    
    # Clean old files
    Remove-Item -LiteralPath $signalPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue
    
    # Background prep work while splash is open
    Start-Job -ArgumentList $rootPath, $progressPath, $signalPath -ScriptBlock {
        param($RootPath, $ProgressPath, $SignalPath)
    
        function Set-Progress([int]$Percent, [string]$Status) {
            @{ progress = $Percent; status = $Status } | ConvertTo-Json | Set-Content -LiteralPath $ProgressPath -Encoding UTF8
        }
    
        try {
            Set-Progress 5  "Starting..."
            Start-Sleep -Milliseconds 200
    
            Set-Progress 20 "Loading config..."
            Import-Module (Join-Path $RootPath "src\Core\Config\Config.psm1") -Force -ErrorAction Stop
    
            Set-Progress 40 "Loading logging..."
            Import-Module (Join-Path $RootPath "src\Core\Logging\Logging.psm1") -Force -ErrorAction Stop
    
            Set-Progress 70 "Loading main window..."
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




    $configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    # -------------------------------------------------
    # Import Config (best effort)
    # -------------------------------------------------
    if (Test-Path $configModule) {
        Import-Module $configModule -Force -ErrorAction SilentlyContinue
    }

    # -------------------------------------------------
    # Import real logging (optional override)
    # -------------------------------------------------
    Write-Host "DEBUG: loggingModule exists = $([bool](Test-Path $loggingModule))"

    if (Test-Path $loggingModule) {
        try {
            Import-Module $loggingModule -Force -ErrorAction Stop
            Write-Host "DEBUG: Logging.psm1 imported successfully"
        } catch {
            Write-Host "DEBUG: Logging.psm1 import failed: $($_.Exception.Message)"
        }
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
    Write-QLog "Intro starting. Root = $rootPath"

    # -------------------------------------------------
    # Import UI helpers (best effort)
    # -------------------------------------------------
    Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1")  -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $rootPath "src\UI\MainWindow.UI.psm1") -Force -ErrorAction SilentlyContinue

    # -------------------------------------------------
    # Optional splash
    # -------------------------------------------------
    $splash = $null
    $minSplashMs = 3000
    $shownAt = $null

    if (-not $SkipSplash -and (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue)) {
        $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
        $splash = New-QOTSplashWindow -Path $splashXaml
        if ($splash) {
            $splash.Show()
            $shownAt = Get-Date
        }
    }

    # -------------------------------------------------
    # Start main window
    # -------------------------------------------------
    Write-QLog "Starting main window"
    #Start-QOTMain -RootPath $rootPath
    Write-QLog "Main window launch deferred to splash"
    
    if ($splash) {
        $elapsed = ((Get-Date) - $shownAt).TotalMilliseconds
        if ($elapsed -lt $minSplashMs) {
            Start-Sleep -Milliseconds ($minSplashMs - $elapsed)
        }
        $splash.Close()
    }

    Write-QLog "Intro completed"
}
finally {
    $WarningPreference = $oldWarningPreference
}
