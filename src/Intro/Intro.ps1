# Intro.ps1
# Fox splash startup for the Quinn Optimiser Toolkit (progress + ready + fade + swap to Main UI)

param(
    [switch]$SkipSplash,
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Logging bootstrap (Intro owns this)
# -------------------------------------------------------------------

if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogPath = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$script:QOTLogPath = $LogPath

# Local function (always available to this script)
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

# Publish to global explicitly (do NOT swallow failures)
Set-Item -Path Function:\global:Write-QLog -Value ${function:Write-QLog} -Force

$oldWarningPreference = $WarningPreference
$WarningPreference    = "SilentlyContinue"

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Ensure a WPF Application exists (prevents null Current in modules that expect it)
    if (-not [System.Windows.Application]::Current) {
        $null = New-Object System.Windows.Application
        [System.Windows.Application]::Current.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    }

    # Paths
    $rootPath       = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModule   = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule  = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule   = Join-Path $rootPath "src\Core\Engine\Engine.psm1"
    $splashUIModule = Join-Path $rootPath "src\Intro\Splash.UI.psm1"
    $splashXaml     = Join-Path $rootPath "src\Intro\Splash.xaml"

    # Splash UI module (best effort)
    if (Test-Path -LiteralPath $splashUIModule) {
        Import-Module $splashUIModule -Force -ErrorAction SilentlyContinue
    }

    $splash = $null
    if (-not $SkipSplash -and (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath $splashXaml) {
            try { $splash = New-QOTSplashWindow -Path $splashXaml } catch { $splash = $null }
        }

        if ($splash) {
            try {
                $splash.WindowStartupLocation = "CenterScreen"
                $splash.Topmost = $true
                $splash.Show()
            } catch { }
        }
    }

    function Set-FoxSplash {
        param(
            [int]$Percent,
            [string]$Text
        )
        if (-not $splash) { return }
        try {
            $splash.Dispatcher.Invoke([action]{
                $bar = $splash.FindName("SplashProgressBar")
                $txt = $splash.FindName("SplashStatusText")
                if ($bar) { $bar.Value = [double]$Percent }
                if ($txt) { $txt.Text  = $Text }
            })
        } catch { }
    }

    function FadeOut-AndCloseFoxSplash {
        if (-not $splash) { return }

        try {
            $splash.Dispatcher.Invoke([action]{
                try { $splash.Topmost = $false } catch { }

                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                $anim.From     = 1
                $anim.To       = 0
                $anim.Duration = [TimeSpan]::FromMilliseconds(300)

                try { $splash.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim) } catch { }
            })
        } catch { }

        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(330)
        $t.Add_Tick({
            $t.Stop()
            try { $splash.Close() } catch { }
        })
        $t.Start()
    }

    function Complete-Intro {
        param([string]$Reason = "normal")

        try {
            Set-FoxSplash 100 "Ready"

            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds(2)
            $timer.Add_Tick({
                $timer.Stop()
                FadeOut-AndCloseFoxSplash
                Write-QLog "Intro completed ($Reason)" "INFO"
                try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch { }
            })
            $timer.Start()
        } catch { }
    }

    # Load config
    Set-FoxSplash 5  "Starting Quinn Optimiser Toolkit..."
    Set-FoxSplash 20 "Loading config..."
    if (Test-Path -LiteralPath $configModule) {
        Import-Module $configModule -Force -ErrorAction SilentlyContinue
    }

    # Load logging (this module might be stomping names, so republish after)
    Set-FoxSplash 40 "Loading logging..."
    if (Test-Path -LiteralPath $loggingModule) {
        Import-Module $loggingModule -Force -ErrorAction SilentlyContinue
    }
    Set-Item -Path Function:\global:Write-QLog -Value ${function:Write-QLog} -Force

    # Load engine
    Set-FoxSplash 65 "Loading engine..."
    if (-not (Test-Path -LiteralPath $engineModule)) {
        throw "Engine module not found at $engineModule"
    }
    Import-Module $engineModule -Force -ErrorAction Stop
    Set-Item -Path Function:\global:Write-QLog -Value ${function:Write-QLog} -Force

    # Start main window
    Set-FoxSplash 85 "Preparing UI..."
    Write-QLog "Starting main window" "INFO"

    $mw = $null
    try {
        $mw = Start-QOTMain -RootPath $rootPath
    } catch {
        Write-QLog "Start-QOTMain threw: $($_.Exception.Message)" "ERROR"
        $mw = $null
    }

    # Fallback completion if ContentRendered never fires
    $fallback = New-Object System.Windows.Threading.DispatcherTimer
    $fallback.Interval = [TimeSpan]::FromSeconds(5)
    $fallback.Add_Tick({
        $fallback.Stop()
        Complete-Intro -Reason "fallback"
    })
    $fallback.Start()

    if ($mw) {
        try {
            $mw.Add_ContentRendered({
                try { $fallback.Stop() } catch { }
                Complete-Intro -Reason "contentrendered"
            })
        } catch {
            try { $fallback.Stop() } catch { }
            Complete-Intro -Reason "contentrendered-hook-failed"
        }
    }
    else {
        try { $fallback.Stop() } catch { }
        Complete-Intro -Reason "mw-null"
    }

    # Keep message pump alive so UI is clickable
    [System.Windows.Threading.Dispatcher]::Run()
}
finally {
    $WarningPreference = $oldWarningPreference
}
