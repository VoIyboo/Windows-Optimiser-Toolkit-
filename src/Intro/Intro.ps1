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

    Set-FoxSplash 75 "Scanning installed apps..."
    Refresh-FoxSplash
    try {
        if (Get-Command Get-QOTInstalledAppsCached -ErrorAction SilentlyContinue) {
            $null = Get-QOTInstalledAppsCached
            try { Write-QLog "Installed apps scan completed during intro." "DEBUG" } catch { }
        } else {
            try { Write-QLog "Installed apps scan skipped; Get-QOTInstalledAppsCached not available." "WARN" } catch { }
        }
    } catch {
        try { Write-QLog ("Installed apps scan during intro failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    Set-FoxSplash 85 "Preparing UI..."
    Refresh-FoxSplash

    & $script:QOTLog "Starting main window" "INFO"

    # MainWindow.UI.psm1 will update splash to Ready, wait 2s, fade, then close.
   Write-Host "[STARTUP] MainWindow warmup started"

    $introReady = New-Object System.Threading.Tasks.TaskCompletionSource[bool]
    $mainReady  = New-Object System.Threading.Tasks.TaskCompletionSource[bool]
    $frame      = New-Object System.Windows.Threading.DispatcherFrame

    $checkReady = {
        if ($introReady.Task.IsCompleted -and $mainReady.Task.IsCompleted) {
            $frame.Continue = $false
        }
    }

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

        & $checkReady
    })

    $mainWindow.Show()

    Write-Host "[STARTUP] Intro finished"
    $null = $introReady.TrySetResult($true)
    & $checkReady

    if (-not ($introReady.Task.IsCompleted -and $mainReady.Task.IsCompleted)) {
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    }

    try { if ($splash) { $splash.Close() } } catch { }

    Write-Host "[STARTUP] Showing MainWindow"

    $mainWindow.ShowInTaskbar = $true
    $mainWindow.ShowActivated = $true
    $mainWindow.Opacity = 1
    $mainWindow.Activate() | Out-Null

    $mainWindow.Add_Closed({
        try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch { }
    })

    & $script:QOTLog "Intro handed off to main window" "INFO"
    [System.Windows.Threading.Dispatcher]::Run()
}
finally {
    $WarningPreference = $oldWarningPreference
}
