# Intro.ps1
# Fox splash startup for the Quinn Optimiser Toolkit (progress + fade + swap to Main UI)

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

        if ($splash) {
            $splash.WindowStartupLocation = "CenterScreen"
            $splash.Topmost = $true
            $splash.Show()
        }
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

    function Refresh-FoxSplash {
        if (-not $splash) { return }
        $splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    function FadeOut-AndCloseFoxSplash {
        if (-not $splash) { return }

        $splash.Dispatcher.Invoke([action]{
            $splash.Topmost = $false

            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
            $anim.From = 1
            $anim.To = 0
            $anim.Duration = [TimeSpan]::FromMilliseconds(300)

            $splash.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
        })

        Start-Sleep -Milliseconds 330

        try {
            $splash.Dispatcher.Invoke([action]{
                $splash.Close()
            })
        } catch { }
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
    $null = Start-QOTMain -RootPath $rootPath
    
    # Wait until the main window is actually loaded and visible
    $waitStart = Get-Date
    while ($true) {
        $mw = $Global:QOTMainWindow
    
        if ($mw -and $mw.IsLoaded -and $mw.IsVisible) { break }
    
        if (((Get-Date) - $waitStart).TotalSeconds -gt 15) { break } # safety timeout
        Start-Sleep -Milliseconds 100
    }
    
    # Now show Ready for 2 seconds, then fade away
    Set-FoxSplash 100 "Ready"
    Refresh-FoxSplash
    Start-Sleep -Seconds 2
    
    FadeOut-AndCloseFoxSplash
    
    Write-QLog "Intro completed" "INFO"
    }
    finally {
        $WarningPreference = $oldWarningPreference
    }
