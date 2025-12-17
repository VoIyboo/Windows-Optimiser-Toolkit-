# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit

param(
    [switch]$SkipSplash,
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# ------------------------------
# Logging path (file path always exists)
# ------------------------------
if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogPath = Join-Path $logDir ("QOT_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}
$script:QOTLogPath = $LogPath

# Silence noisy module import warnings
$oldWarningPreference = $WarningPreference
$WarningPreference = 'SilentlyContinue'

try {
    # ------------------------------
    # WPF assemblies
    # ------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # ------------------------------
    # Work out repo root + module paths
    # ------------------------------
    $rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

    $configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    # ------------------------------
    # Import config (best effort)
    # ------------------------------
    if (Test-Path -LiteralPath $configModule) {
        Import-Module $configModule -Force -ErrorAction SilentlyContinue
    }

# ------------------------------
# Logging MUST load or we fall back
# ------------------------------
$loggingLoaded = $false

try {
    if (-not (Test-Path -LiteralPath $loggingModule)) {
        throw "Logging module not found at: $loggingModule"
    }

    # If an old version is already loaded, purge it first
    $loaded = Get-Module | Where-Object { $_.Path -eq $loggingModule -or $_.Name -eq 'Logging' }
    if ($loaded) {
        Remove-Module -Name $loaded.Name -Force -ErrorAction SilentlyContinue
    }

    $m = Import-Module $loggingModule -Force -ErrorAction Stop -PassThru

    # Prove the functions exist before we continue
    $required = @("Write-QLog", "Set-QLogRoot", "Start-QLogSession")
    foreach ($name in $required) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            throw "Logging module imported from $($m.Path) but $name is not available."
        }
    }

    $loggingLoaded = $true
}
catch {
    # Fallback logging (only if real logging failed)
    function Write-QLog {
        param([string]$Message,[string]$Level="INFO")
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] $Message"
        try { $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8 } catch { }
        if (-not $Quiet) { Write-Host $line }
    }

    function Set-QLogRoot {
        param([Parameter(Mandatory)][string]$Root)
        $script:QLogRoot = $Root
        if (-not (Test-Path -LiteralPath $script:QLogRoot)) {
            New-Item -Path $script:QLogRoot -ItemType Directory -Force | Out-Null
        }
    }

    function Start-QLogSession {
        param([string]$Prefix="QuinnOptimiserToolkit")
        Write-QLog "Log session started (fallback)." "INFO"
    }

    Write-QLog "Logging import failed, using fallback. $($_.Exception.Message)" "WARN"
}


    # ------------------------------
    # Engine is required for Start-QOTMain
    # ------------------------------
    if (-not (Test-Path -LiteralPath $engineModule)) {
        throw "Engine module not found at: $engineModule"
    }
    Import-Module $engineModule -Force -ErrorAction Stop

    # ------------------------------
    # Local config init
    # ------------------------------
    function Initialize-QOTConfig {
        param([Parameter(Mandatory)][string]$RootPath)

        $Global:QOTRoot = $RootPath

        $programDataRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit"
        $logsRoot        = Join-Path $programDataRoot "Logs"

        foreach ($path in @($programDataRoot, $logsRoot)) {
            if (-not (Test-Path -LiteralPath $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
            }
        }

        [pscustomobject]@{
            Root     = $RootPath
            LogsRoot = $logsRoot
        }
    }

    # Import UI helpers (best effort)
    Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1")  -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $rootPath "src\UI\MainWindow.UI.psm1") -Force -ErrorAction SilentlyContinue

    # Initialise config
    $cfg = Initialize-QOTConfig -RootPath $rootPath

    # ------------------------------
    # Safe logging init (guarded)
    # ------------------------------
    if (Get-Command Set-QLogRoot -ErrorAction SilentlyContinue) {
        Set-QLogRoot -Root $cfg.LogsRoot
    } else {
        # Ultra last resort so nothing can break startup
        function Write-QLog {
            param([string]$Message,[string]$Level="INFO")
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $line = "[$ts] [$Level] $Message"
            try { $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8 } catch { }
            if (-not $Quiet) { Write-Host $line }
        }
        Write-QLog "Set-QLogRoot missing. Logging module did not provide expected functions." "WARN"
    }

    if (Get-Command Start-QLogSession -ErrorAction SilentlyContinue) {
        Start-QLogSession
    } else {
        Write-QLog "Start-QLogSession missing. Continuing without session init." "WARN"
    }

    Write-QLog "Intro starting. Root path: $rootPath" "INFO"

    # ------------------------------
    # Optional splash
    # ------------------------------
    $splash = $null
    $script:MinSplashMs   = 3000
    $script:SplashShownAt = $null

    if (-not $SkipSplash) {
        $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"

        if (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue) {
            $splash = New-QOTSplashWindow -Path $splashXaml

            if ($splash) {
                if (Get-Command Update-QOTSplashStatus -ErrorAction SilentlyContinue) {
                    Update-QOTSplashStatus -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
                }
                if (Get-Command Update-QOTSplashProgress -ErrorAction SilentlyContinue) {
                    Update-QOTSplashProgress -Window $splash -Value 5
                }

                try { [void]$splash.Show() } catch { }
                $script:SplashShownAt = Get-Date
            }
        }
    }

    function Set-IntroProgress {
        param(
            [int]$Value,
            [string]$Text
        )

        if ($splash) {
            if ($Text -and (Get-Command Update-QOTSplashStatus -ErrorAction SilentlyContinue)) {
                Update-QOTSplashStatus -Window $splash -Text $Text
            }
            if ($Value -ne $null -and (Get-Command Update-QOTSplashProgress -ErrorAction SilentlyContinue)) {
                Update-QOTSplashProgress -Window $splash -Value $Value
            }

            try { $splash.Dispatcher.Invoke({ }, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }
        }
    }

    Set-IntroProgress -Value 25 -Text "Loading UI..."
    Set-IntroProgress -Value 55 -Text "Initialising modules..."
    Set-IntroProgress -Value 85 -Text "Starting app..."

    Write-QLog "Closing splash and starting main window." "INFO"

    if ($splash) {
        Set-IntroProgress -Value 100 -Text "Ready."

        $elapsedMs = 0
        if ($script:SplashShownAt) {
            $elapsedMs = [int]((Get-Date) - $script:SplashShownAt).TotalMilliseconds
        }

        if ($script:MinSplashMs -and $elapsedMs -lt $script:MinSplashMs) {
            Start-Sleep -Milliseconds ($script:MinSplashMs - $elapsedMs)
        }

        try { $splash.Close() } catch { }
    }

    # ------------------------------
    # Start the main window
    # Engine.psm1 expects -RootPath
    # ------------------------------
    Start-QOTMain -RootPath $rootPath

    Write-QLog "Intro completed." "INFO"

    if (-not $Quiet) {
        Write-Host "Log saved to: $script:QOTLogPath"
    }
}
finally {
    # Restore warning preference
    $WarningPreference = $oldWarningPreference
}
