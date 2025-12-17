# Intro.ps1
# Single splash, single runspace, clean startup

param(
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
$WarningPreference     = "SilentlyContinue"
$VerbosePreference     = "SilentlyContinue"
$InformationPreference = "SilentlyContinue"

# Resolve toolkit root
$rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# WPF
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null

# Splash helpers
Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1") -Force -ErrorAction Stop

$splash = New-QOTSplashWindow -Path (Join-Path $rootPath "src\Intro\Splash.xaml")
Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit (NEW INTRO)..."
Update-QOTSplashProgress -Window $splash -Value 5
[void]$splash.Show()

function Update-Splash {
    param([int]$Value, [string]$Text)

    if ($Text)  { Update-QOTSplashStatus -Window $splash -Text $Text }
    if ($Value) { Update-QOTSplashProgress -Window $splash -Value $Value }

    try {
        $splash.Dispatcher.Invoke({ }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    } catch { }
}

try {
    Update-Splash 20 "Loading engine..."

    # LOAD ENGINE IN MAIN RUNSPACE
    $enginePath = Join-Path $rootPath "src\Core\Engine\Engine.psm1"
    if (-not (Test-Path -LiteralPath $enginePath)) {
        throw "Engine module not found at $enginePath"
    }

    . $enginePath

    if (-not (Get-Command Start-QOTMain -ErrorAction SilentlyContinue)) {
        throw "Start-QOTMain not available after loading Engine.psm1"
    }

    Update-Splash 50 "Initialising modules..."
    Start-Sleep -Milliseconds 300

    Update-Splash 80 "Preparing interface..."
    Start-Sleep -Milliseconds 300

    Update-Splash 100 "Opening app..."
    Start-Sleep -Milliseconds 200

    $splash.Close()

    # START MAIN WINDOW
    Start-QOTMain -RootPath $rootPath
}
catch {
    try { $splash.Close() } catch { }

    [System.Windows.MessageBox]::Show(
        "Startup failed:`n`n$($_.Exception.Message)",
        "Quinn Optimiser Toolkit",
        "OK",
        "Error"
    ) | Out-Null
}
