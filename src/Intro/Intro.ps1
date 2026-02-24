# Intro.ps1
# Fox splash startup for the Quinn Optimiser Toolkit
# Intro coordinates splash display and main window warmup sequencing.

param(
    [switch]$SkipSplash,
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogPath = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$script:QOTLogPath = $LogPath

# This logger is a scriptblock, so it works reliably even when called from other scopes.
$script:QOTLog = {
    param([string]$Message, [string]$Level = "INFO")

    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"

    try { $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8 } catch { }
    if (-not $Quiet) { Write-Host $line }
}

$script:StartupClock = [System.Diagnostics.Stopwatch]::StartNew()
$script:StartupLast  = [TimeSpan]::Zero
$script:StartupTimers = @{}

function Write-StartupMark {
    param([string]$Label)
    $now   = $script:StartupClock.Elapsed
    $delta = $now - $script:StartupLast
    $script:StartupLast = $now
    & $script:QOTLog ("[STARTUP] {0} at {1:hh\:mm\:ss\.fff} (+{2} ms)" -f $Label, $now, [math]::Round($delta.TotalMilliseconds)) "INFO"
}

function Start-StartupChunk {
    param([string]$Name)
    $script:StartupTimers[$Name] = [System.Diagnostics.Stopwatch]::StartNew()
    & $script:QOTLog ("[STARTUP] {0} started" -f $Name) "INFO"
}

function Stop-StartupChunk {
    param(
        [string]$Name,
        [int]$WarnThresholdMs = 200
    )
    if (-not $script:StartupTimers.ContainsKey($Name)) { return }
    $sw = $script:StartupTimers[$Name]
    $sw.Stop()
    $durationMs = [math]::Round($sw.Elapsed.TotalMilliseconds)
    $level = if ($durationMs -ge $WarnThresholdMs) { "WARN" } else { "INFO" }
    & $script:QOTLog ("[STARTUP] {0} finished in {1} ms" -f $Name, $durationMs) $level
}

$oldWarningPreference = $WarningPreference
$WarningPreference    = "SilentlyContinue"

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $rootPath      = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    # Load Splash UI module so New-QOTSplashWindow exists
    $splashUIModule = Join-Path $rootPath "src\Intro\Splash.UI.psm1"
    if (Test-Path $splashUIModule) {
        Import-Module $splashUIModule -Force -ErrorAction SilentlyContinue
    }

    # Create fox splash
    $splash = $null
    if (-not $SkipSplash -and (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue)) {
        $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
        $splash     = New-QOTSplashWindow -Path $splashXaml

        if ($splash) {
            $splash.WindowStartupLocation = "CenterScreen"
            $splash.Topmost = $true
            $splash.Show()
            Write-StartupMark "Intro shown (splash displayed)"
        }
    }
    Write-Host "[STARTUP] Intro started"
    Write-StartupMark "Start heavy init phase 1 (module imports)"
    if (-not $splash) {
        Write-StartupMark "Intro shown (no splash)"
    }

    function Set-FoxSplash {
        param([int]$Percent, [string]$Text)

        if (-not $splash) { return }

        $splash.Dispatcher.Invoke([action]{
            $bar = $splash.FindName("SplashProgressBar")
            $txt = $splash.FindName("SplashStatusText")

            if ($bar) { $bar.Value = [double]$Percent }
            if ($txt) { $txt.Text  = $Text }
        })
    }

    function Refresh-FoxSplash {
        if (-not $splash) { return }
        $splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    Set-FoxSplash 5  "Starting Quinn Optimiser Toolkit..."
    Refresh-FoxSplash
    Start-Sleep -Milliseconds 150

    Set-FoxSplash 20 "Loading config..."
    Refresh-FoxSplash
    Start-StartupChunk "Load config module"
    if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction SilentlyContinue }
    Stop-StartupChunk "Load config module"

    Set-FoxSplash 40 "Loading logging..."
    Refresh-FoxSplash
    Start-StartupChunk "Load logging module"
    if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction SilentlyContinue }
    Stop-StartupChunk "Load logging module"

    Set-FoxSplash 65 "Loading engine..."
    Refresh-FoxSplash
    Start-StartupChunk "Load engine module"
    if (-not (Test-Path $engineModule)) { throw "Engine module not found at $engineModule" }
    Import-Module $engineModule -Force -ErrorAction Stop
    Stop-StartupChunk "Load engine module"
    Write-StartupMark "Finish module imports"

    Set-FoxSplash 70 "Preparing startup tasks..."
    Refresh-FoxSplash
    Start-StartupChunk "Startup runspace preparation"

    $startupState = [hashtable]::Synchronized(@{
        Percent   = 70
        Status    = "Preparing startup tasks..."
        Completed = $false
        Error     = $null
    })

    $startupRunspace = [runspacefactory]::CreateRunspace()
    $startupRunspace.ApartmentState = "MTA"
    $startupRunspace.ThreadOptions  = "ReuseThread"
    $startupRunspace.Open()

    $startupPs = [powershell]::Create()
    $startupPs.Runspace = $startupRunspace
    $null = $startupPs.AddScript({
        param(
            [string]$RootPath,
            [hashtable]$State,
            [string]$LogPath
        )

        $ErrorActionPreference = "Stop"

        function Set-IntroState {
            param([int]$Percent, [string]$Text)
            $State.Percent = $Percent
            $State.Status  = $Text
        }

        function Write-IntroLog {
            param([string]$Message, [string]$Level = "INFO")
            $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            $line = "[$ts] [$Level] $Message"
            try { $line | Add-Content -Path $LogPath -Encoding UTF8 } catch { }
        }

        function Invoke-IntroChunk {
            param(
                [string]$Name,
                [scriptblock]$Action,
                [int]$WarnThresholdMs = 200
            )

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Write-IntroLog "[STARTUP] $Name started"
            & $Action
            $sw.Stop()
            $durationMs = [math]::Round($sw.Elapsed.TotalMilliseconds)
            $level = if ($durationMs -ge $WarnThresholdMs) { "WARN" } else { "INFO" }
            Write-IntroLog ("[STARTUP] {0} finished in {1} ms [{2}]" -f $Name, $durationMs, $level) $level
        }

        try {
            Set-IntroState 72 "Loading settings..."
            Write-IntroLog "[STARTUP] Load settings JSON start"
            Invoke-IntroChunk "Load settings data" {
                $settingsModule = Join-Path $RootPath "src\Core\Settings.psm1"
                if (Test-Path $settingsModule) {
                    Import-Module $settingsModule -Force -ErrorAction Stop
                    if (Get-Command Get-QOSettings -ErrorAction SilentlyContinue) {
                        $null = Get-QOSettings
                    }
                }
            }

            Write-IntroLog "[STARTUP] Load settings JSON end"

            Set-IntroState 76 "Loading tickets..."
            Write-IntroLog "[STARTUP] Load tickets JSON start"
            Invoke-IntroChunk "Load ticket data" {
                $ticketsModule = Join-Path $RootPath "src\Core\Tickets.psm1"
                if (Test-Path $ticketsModule) {
                    Import-Module $ticketsModule -Force -ErrorAction Stop
                    if (Get-Command Get-QOTickets -ErrorAction SilentlyContinue) {
                        $null = Get-QOTickets
                    }
                }
            }

            Write-IntroLog "[STARTUP] Load tickets JSON end"

            Set-IntroState 80 "Scanning installed apps..."
            Write-IntroLog "[STARTUP] File system scan start (installed apps)"
            Invoke-IntroChunk "Scan installed apps" {
                $appsModule = Join-Path $RootPath "src\Apps\InstalledApps.psm1"
                if (Test-Path $appsModule) {
                    Import-Module $appsModule -Force -ErrorAction Stop
                    if (Get-Command Get-QOTInstalledAppsCached -ErrorAction SilentlyContinue) {
                        $null = Get-QOTInstalledAppsCached
                    }
                }
            }
            Write-IntroLog "[STARTUP] File system scan end (installed apps)"

            Set-IntroState 84 "Running startup warmup..."
            Invoke-IntroChunk "Run startup warmup" {
                $engineModule = Join-Path $RootPath "src\Core\Engine\Engine.psm1"
                if (Test-Path $engineModule) {
                    Import-Module $engineModule -Force -ErrorAction Stop
                    if (Get-Command Invoke-QOTStartupWarmup -ErrorAction SilentlyContinue) {
                        Invoke-QOTStartupWarmup -RootPath $RootPath
                    }
                }
            }

            Set-IntroState 88 "Finalising startup..."
            Start-Sleep -Milliseconds 150

            $State.Completed = $true
        }

       catch {
            $State.Error = $_.Exception.ToString()
            $State.Completed = $true
            throw
        }
    }).AddArgument($rootPath).AddArgument($startupState).AddArgument($script:QOTLogPath)

    Stop-StartupChunk "Startup runspace preparation"
    Start-StartupChunk "Startup background tasks"

    $startupAsync = $startupPs.BeginInvoke()

    $startupFrame = New-Object System.Windows.Threading.DispatcherFrame
    $startupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $startupTimeoutMs = 45000
    $startupTimeoutHit = $false
    $startupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startupTimer.Interval = [TimeSpan]::FromMilliseconds(120)
    $startupTimer.Add_Tick({
        if ($startupState.Status) {
            Set-FoxSplash $startupState.Percent $startupState.Status
        }
        if ($startupAsync.IsCompleted) {
            $startupTimer.Stop()
            $startupFrame.Continue = $false
            return
        }

        if ($startupStopwatch.ElapsedMilliseconds -ge $startupTimeoutMs) {
            $startupTimeoutHit = $true
            $startupState.Status = "Startup warmup timed out, continuing..."
            $startupTimer.Stop()
            $startupFrame.Continue = $false
        }
    })
    $startupTimer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($startupFrame)

    try {
        if ($startupTimeoutHit) {
            try {
                $startupPs.Stop()
            } catch { }
            & $script:QOTLog ("[STARTUP] Background startup tasks timed out after {0} ms. Continuing with main window initialisation." -f $startupTimeoutMs) "WARN"
        } else {
            $null = $startupPs.EndInvoke($startupAsync)
        }
    } finally {
        $startupStopwatch.Stop()
        $startupPs.Dispose()
        $startupRunspace.Dispose()
    }
    Stop-StartupChunk "Startup background tasks"

    if ($startupState.Error) {
        throw $startupState.Error
    }

    Set-FoxSplash 92 "Building main window..."
    Refresh-FoxSplash

    Start-StartupChunk "MainWindow launch"
    & $script:QOTLog "Starting main window" "INFO"
    Write-Host "[STARTUP] MainWindow launch started"

    # Route through Start-QOTMain without WarmupOnly so the window lifecycle
    # is owned by MainWindow.UI.psm1 (Show + app.Run) on a single code path.
    #
    # Some deployments have reported Start-QOTMain returning immediately after
    # startup logs report "Starting main window", leaving users with no visible
    # UI. If that happens in the first couple seconds, attempt a direct
    # Start-QOTMainWindow fallback path so the app can still recover.
    $mainWindowLaunchTimer = [System.Diagnostics.Stopwatch]::StartNew()
    Start-QOTMain -RootPath $rootPath -SplashWindow $splash
    $mainWindowLaunchTimer.Stop()
    if ($mainWindowLaunchTimer.Elapsed.TotalSeconds -lt 3) {
        & $script:QOTLog ("[STARTUP] Start-QOTMain returned after {0} ms; attempting direct MainWindow fallback launch." -f [math]::Round($mainWindowLaunchTimer.Elapsed.TotalMilliseconds)) "WARN"

        $mainWindowModulePath = Join-Path $rootPath "src\UI\MainWindow.UI.psm1"
        if (-not (Get-Command Start-QOTMainWindow -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path -LiteralPath $mainWindowModulePath)) {
                throw "MainWindow UI module not found for fallback launch: $mainWindowModulePath"
            }
            Import-Module $mainWindowModulePath -Force -ErrorAction Stop
        }
        Start-QOTMainWindow -RootPath $rootPath -SplashWindow $splash
    }

    Write-StartupMark "MainWindow run loop exited"
    & $script:QOTLog "MainWindow run loop exited" "INFO"
    Stop-StartupChunk "MainWindow launch"
}
finally {
    $WarningPreference = $oldWarningPreference
}
