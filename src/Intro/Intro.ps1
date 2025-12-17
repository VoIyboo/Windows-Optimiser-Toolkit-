# Intro.ps1
# Responsible ONLY for splash + startup sequencing (single splash)

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
# Show splash immediately
# --------------------------------------
$splash = New-QOTSplashWindow -Path (Join-Path $rootPath "src\Intro\Splash.xaml")
Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
Update-QOTSplashProgress -Window $splash -Value 5
[void]$splash.Show()

# --------------------------------------
# Background init (NO UI touching in here)
# --------------------------------------
$ps = [PowerShell]::Create()
$null = $ps.AddScript({
    param($Root)

    $ErrorActionPreference = "Stop"

    $engine = Join-Path $Root "src\Core\Engine\Engine.psm1"
    Import-Module $engine -Force -ErrorAction Stop

    # Optional light warmups only (safe, quick)
    try { if (Get-Command Test-QOTWingetAvailable -ErrorAction SilentlyContinue) { $null = Test-QOTWingetAvailable } } catch { }
    try { if (Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue) { $null = Get-QOTCommonAppsCatalogue } } catch { }

    return $true
}).AddArgument($rootPath)

$async = $ps.BeginInvoke()

# --------------------------------------
# Progress loop (keeps splash responsive)
# --------------------------------------
$progress = 10
while (-not $async.IsCompleted) {

    $progress = [Math]::Min(90, $progress + 2)

    Update-QOTSplashStatus   -Window $splash -Text "Loading modules..."
    Update-QOTSplashProgress -Window $splash -Value $progress

    # Let WPF paint (very important)
    try { $splash.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }

    Start-Sleep -Milliseconds 120
}

# --------------------------------------
# Finish background init
# --------------------------------------
try {
    $null = $ps.EndInvoke($async)

    Update-QOTSplashStatus   -Window $splash -Text "Opening app..."
    Update-QOTSplashProgress -Window $splash -Value 100

    try { $splash.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }
}
catch {
    [System.Windows.MessageBox]::Show(
        "Startup failed:`n`n$($_.Exception.Message)",
        "Quinn Optimiser Toolkit",
        "OK",
        "Error"
    ) | Out-Null

    try { $splash.Close() } catch { }
    return
}
finally {
    try { $ps.Dispose() } catch { }
}

# --------------------------------------
# Start main window
# Do NOT close splash here, the main window will close it on load
# --------------------------------------
# Make Start-QOTMain available in the main session (runspace imports do not carry over)
while (-not $async.IsCompleted) {
    $progress = [Math]::Min(90, $progress + 3)

    Update-QOTSplashStatus   -Window $splash -Text "Loading modules..."
    Update-QOTSplashProgress -Window $splash -Value $progress

    try {
        $splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    } catch { }

    Start-Sleep -Milliseconds 120
}

Update-QOTSplashStatus   -Window $splash -Text "Opening app..."
Update-QOTSplashProgress -Window $splash -Value 100

try {
    $splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
} catch { }

Start-Sleep -Milliseconds 150

try { $splash.Close() } catch { }
Start-QOTMain -RootPath $rootPath
