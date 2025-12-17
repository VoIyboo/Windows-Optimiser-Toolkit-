# Intro.ps1
# Fox splash startup for the Quinn Optimiser Toolkit (progress + ready + fade + swap to Main UI)

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

function Write-QLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    try { $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8 } catch { }
    if (-not $Quiet) { Write-Host $line }
}

$oldWarningPreference = $WarningPreference
$WarningPreference = "SilentlyContinue"

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $rootPath      = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    $splashUIModule = Join-Path $rootPath "src\Intro\Splash.UI.psm1"
    if (Test-Path $splashUIModule) {
        Import-Module $splashUIModule -Force -ErrorAction SilentlyContinue
    }

    $splash = $null
    if (-not $SkipSplash -and (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue)) {
        $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
        $splash = New-QOTSplashWindow -Path $splashXaml

        if ($splash) {
            $splash.WindowStartupLocation = "CenterScreen"
            $splash.Topmost = $true
            $splash.Show()
        }
    }

    # =================================================================
    # Scriptblocks stored in variables (callable inside event handlers)
    # =================================================================

    $script:SetFoxSplash = {
        param([int]$Percent, [string]$Text)

        if (-not $splash) { return }

        $splash.Dispatcher.Invoke([action]{
            $bar = $splash.FindName("SplashProgressBar")
            $txt = $splash.FindName("SplashStatusText")
            if ($bar) { $bar.Value = [double]$Percent }
            if ($txt) { $txt.Text = $Text }
        })
    }.GetNewClosure()

    $script:FadeOutAndClose = {
        if (-not $splash) { return }

        $splash.Dispatcher.Invoke([action]{
            $splash.Topmost = $false

            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
            $anim.From = 1
            $anim.To = 0
            $anim.Duration = [TimeSpan]::FromMilliseconds(300)

            $splash.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
        })

        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(330)

        $tLocal = $t
        $t.Add_Tick( ({
            $tLocal.Stop()
            try { $splash.Close() } catch { }
        }).GetNewClosure() )

        $t.Start()
    }.GetNewClosure()

    $script:CompleteIntro = {
        param([string]$Reason = "normal")

        try {
            & $script:SetFoxSplash 100 "Ready"

            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds(2)

            $timerLocal = $timer
            $timer.Add_Tick( ({
                $timerLocal.Stop()
                & $script:FadeOutAndClose
                Write-QLog "Intro completed ($Reason)" "INFO"
            }).GetNewClosure() )

            $timer.Start()
        } catch { }
    }.GetNewClosure()

    # =================================================================
    # Startup sequence
    # =================================================================

    & $script:SetFoxSplash 5  "Starting Quinn Optimiser Toolkit..."
    & $script:SetFoxSplash 20 "Loading config..."
    if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction SilentlyContinue }

    & $script:SetFoxSplash 40 "Loading logging..."
    if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction SilentlyContinue }

    & $script:SetFoxSplash 65 "Loading engine..."
    if (-not (Test-Path $engineModule)) { throw "Engine module not found at $engineModule" }
    Import-Module $engineModule -Force -ErrorAction Stop

    & $script:SetFoxSplash 85 "Preparing UI..."
    Write-QLog "Starting main window" "INFO"

    $mw = $null
    try {
        $mw = Start-QOTMain -RootPath $rootPath
    } catch {
        Write-QLog ("Start-QOTMain failed: " + $_.Exception.Message) "ERROR"
        throw
    }

    $app = [System.Windows.Application]::Current
    if (-not $app) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnLastWindowClose
    }

    # Fallback if ContentRendered never fires
    $fallback = New-Object System.Windows.Threading.DispatcherTimer
    $fallback.Interval = [TimeSpan]::FromSeconds(5)

    $fallbackLocal = $fallback
    $fallback.Add_Tick( ({
        $fallbackLocal.Stop()
        & $script:CompleteIntro "fallback"
    }).GetNewClosure() )

    $fallback.Start()

    if ($mw) {
        $mw.Add_ContentRendered( ({
            try { $fallbackLocal.Stop() } catch { }
            & $script:CompleteIntro "contentrendered"
        }).GetNewClosure() )

        try { if (-not $mw.IsVisible) { $mw.Show() } } catch { }

        [void]$app.Run()
    }
    else {
        try { $fallbackLocal.Stop() } catch { }
        & $script:CompleteIntro "mw-null"
        try { $app.Shutdown() } catch { }
    }
}
finally {
    $WarningPreference = $oldWarningPreference
}
