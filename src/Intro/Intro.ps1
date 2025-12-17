# Intro.ps1
# Responsible ONLY for splash + startup sequencing

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
# Load minimal logging if available
# --------------------------------------
$loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
if (Test-Path $loggingModule) {
    Import-Module $loggingModule -Force -ErrorAction SilentlyContinue
}

try { Write-QLog "Intro started. Root=$rootPath" } catch { }

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
$splash.Show()

# --------------------------------------
# Run background init on separate runspace
# --------------------------------------
$ps = [PowerShell]::Create()
$null = $ps.AddScript({
    param($Root)

    $ErrorActionPreference = "Stop"

    # Load engine (this imports all feature modules)
    $engine = Join-Path $Root "src\Core\Engine\Engine.psm1"
    Import-Module $engine -Force -ErrorAction Stop

    # Optional warm-up work
    if (Get-Command Refresh-QOTInstalledAppsGrid -ErrorAction SilentlyContinue) {
        Refresh-QOTInstalledAppsGrid -Grid $null 2>$null
    }

    if (Get-Command Refresh-QOTCommonAppsGrid -ErrorAction SilentlyContinue) {
        Refresh-QOTCommonAppsGrid -Grid $null 2>$null
    }

    return $true
}).AddArgument($rootPath)

$async = $ps.BeginInvoke()

# --------------------------------------
# Simple splash progress loop
# --------------------------------------
$progress = 10
while (-not $async.IsCompleted) {
    $progress = [Math]::Min(90, $progress + 3)
    Update-QOTSplashStatus   -Window $splash -Text "Loading modules..."
    Update-QOTSplashProgress -Window $splash -Value $progress
    Start-Sleep -Milliseconds 120
}

try {
    $ps.EndInvoke($async)
    Update-QOTSplashStatus   -Window $splash -Text "Opening app..."
    Update-QOTSplashProgress -Window $splash -Value 100
}
catch {
    [System.Windows.MessageBox]::Show(
        "Startup failed:`n`n$($_.Exception.Message)",
        "Quinn Optimiser Toolkit",
        "OK",
        "Error"
    ) | Out-Null

    $splash.Close()
    return
}
finally {
    $ps.Dispose()
}

Start-Sleep -Milliseconds 200
$splash.Close()

# --------------------------------------
# Start main window
# --------------------------------------
Start-QOTMain -RootPath $rootPath
