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
# WPF assemblies
# --------------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# --------------------------------------
# Load logging if available
# --------------------------------------
$loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
if (Test-Path -LiteralPath $loggingModule) {
    Import-Module $loggingModule -Force -ErrorAction SilentlyContinue
}

try { Write-QLog "Intro started. Root=$rootPath" } catch { }

# --------------------------------------
# Load splash helpers and show splash
# --------------------------------------
Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1") -Force -ErrorAction Stop

$splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
$splash     = New-QOTSplashWindow -Path $splashXaml

Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
Update-QOTSplashProgress -Window $splash -Value 5
$null = $splash.Show()

# Let WPF paint the splash immediately
try { $splash.Dispatcher.Invoke({ }, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }

# --------------------------------------
# Load Engine now (imports feature modules)
# Keep it simple and safe, no grid refresh here
# --------------------------------------
try {
    Update-QOTSplashStatus   -Window $splash -Text "Loading modules..."
    Update-QOTSplashProgress -Window $splash -Value 35

    $engine = Join-Path $rootPath "src\Core\Engine\Engine.psm1"
    if (-not (Test-Path -LiteralPath $engine)) {
        throw "Engine module not found at: $engine"
    }

    Import-Module $engine -Force -ErrorAction Stop

    Update-QOTSplashStatus   -Window $splash -Text "Opening app..."
    Update-QOTSplashProgress -Window $splash -Value 90
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

# --------------------------------------
# Start main window WHILE splash is visible
# Main window is responsible for closing splash when ready
# --------------------------------------
try {
    Start-QOTMain -RootPath $rootPath -SplashWindow $splash
}
catch {
    try { Write-QLog "Start-QOTMain failed: $($_.Exception.Message)" "ERROR" } catch { }
    try { $splash.Close() } catch { }
    throw
}
