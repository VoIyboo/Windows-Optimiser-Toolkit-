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
        }
    }
    Write-Host "[STARTUP] Intro started"

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
    if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction SilentlyContinue }

    Set-FoxSplash 40 "Loading logging..."
    Refresh-FoxSplash
    if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction SilentlyContinue }

    Set-FoxSplash 65 "Loading engine..."
    Refresh-FoxSplash
    if (-not (Test-Path $engineModule)) { throw "Engine module not found at $engineModule" }
    Import-Module $engineModule -Force -ErrorAction Stop

    Set-FoxSplash 70 "Preparing startup tasks..."
    Refresh-FoxSplash

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
            [hashtable]$State
        )

        $ErrorActionPreference = "Stop"

        function Set-IntroState {
            param([int]$Percent, [string]$Text)
            $State.Percent = $Percent
            $State.Status  = $Text
        }

        try {
            Set-IntroState 72 "Loading settings..."
            $settingsModule = Join-Path $RootPath "src\Core\Settings.psm1"
            if (Test-Path $settingsModule) {
                Import-Module $settingsModule -Force -ErrorAction Stop
                if (Get-Command Get-QOSettings -ErrorAction SilentlyContinue) {
                    $null = Get-QOSettings
                }
            }

            Set-IntroState 76 "Loading tickets..."
            $ticketsModule = Join-Path $RootPath "src\Core\Tickets.psm1"
            if (Test-Path $ticketsModule) {
                Import-Module $ticketsModule -Force -ErrorAction Stop
                if (Get-Command Get-QOTickets -ErrorAction SilentlyContinue) {
                    $null = Get-QOTickets
                }
            }

            Set-IntroState 80 "Scanning installed apps..."
            $appsModule = Join-Path $RootPath "src\Apps\InstalledApps.psm1"
            if (Test-Path $appsModule) {
                Import-Module $appsModule -Force -ErrorAction Stop
                if (Get-Command Get-QOTInstalledAppsCached -ErrorAction SilentlyContinue) {
                    $null = Get-QOTInstalledAppsCached
                }
            }

            Set-IntroState 84 "Running startup warmup..."
            $engineModule = Join-Path $RootPath "src\Core\Engine\Engine.psm1"
            if (Test-Path $engineModule) {
                Import-Module $engineModule -Force -ErrorAction Stop
                if (Get-Command Invoke-QOTStartupWarmup -ErrorAction SilentlyContinue) {
                    Invoke-QOTStartupWarmup
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
    }).AddArgument($rootPath).AddArgument($startupState)

    $startupAsync = $startupPs.BeginInvoke()

    $startupFrame = New-Object System.Windows.Threading.DispatcherFrame
    $startupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $startupTimer.Interval = [TimeSpan]::FromMilliseconds(120)
    $startupTimer.Add_Tick({
        if ($startupState.Status) {
            Set-FoxSplash $startupState.Percent $startupState.Status
        }
        if ($startupAsync.IsCompleted) {
            $startupTimer.Stop()
            $startupFrame.Continue = $false
        }
    })
    $startupTimer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($startupFrame)

    try {
        $null = $startupPs.EndInvoke($startupAsync)
    } finally {
        $startupPs.Dispose()
        $startupRunspace.Dispose()
    }

    if ($startupState.Error) {
        throw $startupState.Error
    }

    Set-FoxSplash 92 "Building main window..."
    Refresh-FoxSplash

    & $script:QOTLog "Starting main window" "INFO"

    # MainWindow.UI.psm1 will update splash to Ready, wait 2s, fade, then close.
   Write-Host "[STARTUP] MainWindow warmup started"

    $mainReady  = New-Object System.Threading.Tasks.TaskCompletionSource[bool]
    $renderFrame = New-Object System.Windows.Threading.DispatcherFrame

    $mainWindow = Start-QOTMain -RootPath $rootPath -SplashWindow $splash -WarmupOnly -PassThru
    if (-not $mainWindow) {
        throw "MainWindow warmup failed to create window."
    }

    $mainWindow.Opacity        = 0
    $mainWindow.ShowActivated  = $false
    $mainWindow.ShowInTaskbar  = $false

    $mainWindow.Add_ContentRendered({
        if (-not $mainReady.Task.IsCompleted) {
            $null = $mainReady.TrySetResult($true)
            Write-Host "[STARTUP] MainWindow warmup done"
        }

        $renderFrame.Continue = $false
    })

    $mainWindow.Show()
    $mainWindow.UpdateLayout()
    $mainWindow.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    if (-not $mainReady.Task.IsCompleted) {
        [System.Windows.Threading.Dispatcher]::PushFrame($renderFrame)
    }

    Write-Host "[STARTUP] Intro finished"

    Write-Host "[STARTUP] Showing MainWindow"

    $mainWindow.ShowInTaskbar = $true
    $mainWindow.ShowActivated = $true
    $mainWindow.Opacity = 1
    $mainWindow.Activate() | Out-Null

    try { if ($splash) { $splash.Close() } } catch { }

    $mainWindow.Add_Closed({
        try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch { }
    })

    & $script:QOTLog "Intro handed off to main window" "INFO"
    [System.Windows.Threading.Dispatcher]::Run()
}
finally {
    $WarningPreference = $oldWarningPreference
}
