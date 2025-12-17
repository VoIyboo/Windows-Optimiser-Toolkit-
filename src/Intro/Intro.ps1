# Intro.ps1
# Responsible ONLY for splash + startup sequencing (single splash, no second one)

param(
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# --------------------------------------
# Resolve toolkit root
# src\Intro\Intro.ps1 -> toolkit root
# --------------------------------------
$rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# --------------------------------------
# WPF
# --------------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# --------------------------------------
# Load splash helpers
# --------------------------------------
Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1") -Force -ErrorAction Stop

# --------------------------------------
# Create + show splash immediately
# --------------------------------------
$splash = New-QOTSplashWindow -Path (Join-Path $rootPath "src\Intro\Splash.xaml")
Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
Update-QOTSplashProgress -Window $splash -Value 5
[void]$splash.Show()

# --------------------------------------
# Start background init (no UI touching here)
# --------------------------------------
$ps = [PowerShell]::Create()
$null = $ps.AddScript({
    param($Root)

    $ErrorActionPreference = "Stop"

    $engine = Join-Path $Root "src\Core\Engine\Engine.psm1"
    Import-Module $engine -Force -ErrorAction Stop

    # Optional: light warmups only (no grids, no UI)
    try { if (Get-Command Test-QOTWingetAvailable -ErrorAction SilentlyContinue) { $null = Test-QOTWingetAvailable } } catch { }
    try { if (Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue) { $null = Get-QOTCommonAppsCatalogue } } catch { }

    return $true
}).AddArgument($rootPath)

$async = $ps.BeginInvoke()

# --------------------------------------
# Progress timer (keeps UI responsive)
# --------------------------------------
$progress = 8
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)

$timer.Add_Tick({
    if ($async.IsCompleted) {
        $timer.Stop()
        return
    }

    $progress = [Math]::Min(90, $progress + 2)
    Update-QOTSplashStatus   -Window $splash -Text "Loading modules..."
    Update-QOTSplashProgress -Window $splash -Value $progress
})

$timer.Start()

# --------------------------------------
# When background init completes, open main window
# --------------------------------------
$splash.Dispatcher.BeginInvoke([Action]{
    try {
        while (-not $async.IsCompleted) {
            Start-Sleep -Milliseconds 80
        }

        $null = $ps.EndInvoke($async)

        Update-QOTSplashStatus   -Window $splash -Text "Opening app..."
        Update-QOTSplashProgress -Window $splash -Value 100

        # Hand splash window into Start-QOTMain so MainWindow can close it when loaded
        Start-QOTMain -RootPath $rootPath -SplashWindow $splash
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Startup failed:`n`n$($_.Exception.Message)",
            "Quinn Optimiser Toolkit",
            "OK",
            "Error"
        ) | Out-Null

        try { $splash.Close() } catch { }
    }
    finally {
        try { $ps.Dispose() } catch { }
        try { $timer.Stop() } catch { }
    }
}, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
})

# Keep script alive until splash closes (then main window takes over)
[void][System.Windows.Threading.Dispatcher]::Run()
