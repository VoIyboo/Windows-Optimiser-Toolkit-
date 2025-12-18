 Intro.ps1
# Fox splash startup for the Quinn Optimiser Toolkit (progress + fade + swap to Main UI)
# Fox splash startup for the Quinn Optimiser Toolkit (progress + ready + fade + swap to Main UI)

param(
    [switch]$SkipSplash,
@@ -9,9 +9,6 @@ param(

$ErrorActionPreference = "Stop"

# -------------------------------------------------
# Log file path (always exists)
# -------------------------------------------------
if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path $logDir)) {
@@ -21,52 +18,34 @@ if (-not $LogPath) {
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

# -------------------------------------------------
# Silence noisy warnings
# -------------------------------------------------
$oldWarningPreference = $WarningPreference
$WarningPreference = "SilentlyContinue"

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # -------------------------------------------------
    # Resolve root + module paths
    # -------------------------------------------------
    $rootPath      = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
    $loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
    $engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

    # -------------------------------------------------
    # Import Splash UI so New-QOTSplashWindow exists
    # -------------------------------------------------
    $splashUIModule = Join-Path $rootPath "src\Intro\Splash.UI.psm1"
    if (Test-Path $splashUIModule) {
        Import-Module $splashUIModule -Force -ErrorAction SilentlyContinue
    }

    # -------------------------------------------------
    # Fox splash (Splash.xaml)
    # -------------------------------------------------
    $splash = $null

    if (-not $SkipSplash -and (Get-Command New-QOTSplashWindow -ErrorAction SilentlyContinue)) {
        $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
        $splash = New-QOTSplashWindow -Path $splashXaml
@@ -83,130 +62,78 @@ try {
            [int]$Percent,
            [string]$Text
        )

        if (-not $splash) { return }

        try {
            $splash.Dispatcher.Invoke([action]{
                $bar = $splash.FindName("SplashProgressBar")
                $txt = $splash.FindName("SplashStatusText")

                if ($bar) { $bar.Value = [double]$Percent }
                if ($txt) { $txt.Text = $Text }
            })
        } catch { }
    }

    function Refresh-FoxSplash {
        if (-not $splash) { return }
        try {
            $splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        } catch { }
        $splash.Dispatcher.Invoke([action]{
            $bar = $splash.FindName("SplashProgressBar")
            $txt = $splash.FindName("SplashStatusText")
            if ($bar) { $bar.Value = [double]$Percent }
            if ($txt) { $txt.Text = $Text }
        })
    }

    function FadeOut-AndCloseFoxSplash {
        if (-not $splash) { return }

        try {
            $splash.Dispatcher.Invoke([action]{
                $splash.Topmost = $false

                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                $anim.From = 1
                $anim.To = 0
                $anim.Duration = [TimeSpan]::FromMilliseconds(300)
        $splash.Dispatcher.Invoke([action]{
            $splash.Topmost = $false

                $splash.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
            })
        } catch { }
            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
            $anim.From = 1
            $anim.To = 0
            $anim.Duration = [TimeSpan]::FromMilliseconds(300)

        Start-Sleep -Milliseconds 330
            $splash.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
        })

        try {
            $splash.Dispatcher.Invoke([action]{ $splash.Close() })
        } catch { }
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(330)
        $t.Add_Tick({
            $t.Stop()
            try { $splash.Close() } catch { }
        })
        $t.Start()
    }

    # -------------------------------------------------
    # Loading stages shown on fox splash
    # -------------------------------------------------
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

    Set-FoxSplash 85 "Preparing UI..."
    Refresh-FoxSplash
    Start-Sleep -Milliseconds 200

    # -------------------------------------------------
    # Start main UI while splash is still visible
    # -------------------------------------------------
    Write-QLog "Starting main window" "INFO"

    # Start main window (expects Engine.Start-QOTMain to set $Global:QOTMainWindow)
    $null = Start-QOTMain -RootPath $rootPath

    # Wait until the main window is actually visible (max 15s)
    $waitStart = Get-Date
    while ($true) {
        $mw = $Global:QOTMainWindow

        # Use IsVisible + IsLoaded when available, but don’t crash if property missing
        $isVisible = $false
        $isLoaded  = $false

        try { if ($mw) { $isVisible = [bool]$mw.IsVisible } } catch { }
        try { if ($mw) { $isLoaded  = [bool]$mw.IsLoaded  } } catch { }

        if ($mw -and ($isVisible -or $isLoaded)) {
            break
        }

        if (((Get-Date) - $waitStart).TotalSeconds -gt 15) {
            Write-QLog "UI ready timeout, continuing anyway" "WARN"
            break
        }

        Start-Sleep -Milliseconds 100
    $mw = Start-QOTMain -RootPath $rootPath

    if ($mw) {
        $mw.Add_ContentRendered({
            try {
                Set-FoxSplash 100 "Ready"

                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromSeconds(2)
                $timer.Add_Tick({
                    $timer.Stop()
                    FadeOut-AndCloseFoxSplash
                    Write-QLog "Intro completed" "INFO"
                })
                $timer.Start()
            } catch { }
        })
    }
    else {
        Set-FoxSplash 100 "Ready"
        FadeOut-AndCloseFoxSplash
        Write-QLog "Intro completed" "INFO"
    }

    # Now show Ready for 2 seconds, then fade away
    Set-FoxSplash 100 "Ready"
    Refresh-FoxSplash
    Start-Sleep -Seconds 2

    FadeOut-AndCloseFoxSplash

    Write-QLog "Intro completed" "INFO"
    # Keep message pump alive so UI is clickable
    [System.Windows.Threading.Dispatcher]::Run()
}
finally {
    $WarningPreference = $oldWarningPreference
}

# Keep the UI alive after splash closes (only if we created the main window)
if ($Global:QOTMainWindow) {
    try {
        $disp = [System.Windows.Threading.Dispatcher]::FromThread([System.Threading.Thread]::CurrentThread)

        # If there is no dispatcher loop yet, start it
        if ($null -eq $disp) {
            [System.Windows.Threading.Dispatcher]::Run()
        }
    } catch {
        # If we can't run the dispatcher, just exit gracefully
    }
}
