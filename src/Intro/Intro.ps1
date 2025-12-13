# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit

param(
    [switch]$SkipSplash
)

$ErrorActionPreference = "Stop"

# Make sure WPF assemblies are available
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Work out repo root:
$rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Paths to core modules
$configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
$loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
$engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

# Import core modules
Import-Module $configModule  -Force
Import-Module $loggingModule -Force
Import-Module $engineModule  -Force

# -------------------------------------------------------------------
# Safety net logging fallbacks
# -------------------------------------------------------------------
if (-not (Get-Command Set-QLogRoot -ErrorAction SilentlyContinue)) {
    function Set-QLogRoot {
        param([string]$Root)
        $Global:QOTLogRoot = $Root
        Write-Host "[INFO] Set-QLogRoot fallback: $Root"
    }
}

if (-not (Get-Command Start-QLogSession -ErrorAction SilentlyContinue)) {
    function Start-QLogSession {
        param([string]$Prefix = "QuinnOptimiserToolkit")
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$ts] [INFO] Log session started (fallback in Intro.ps1)."
    }
}

if (-not (Get-Command Write-QLog -ErrorAction SilentlyContinue)) {
    function Write-QLog {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$ts] [$Level] $Message"
    }
}

# -------------------------------------------------------------------
# Local bootstrap version of Initialize-QOTConfig
# -------------------------------------------------------------------
function Initialize-QOTConfig {
    param([string]$RootPath)

    $root = if ($RootPath) { $RootPath } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
    $Global:QOTRoot = $root

    $programDataRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit"
    $logsRoot        = Join-Path $programDataRoot "Logs"

    foreach ($path in @($programDataRoot, $logsRoot)) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }

    [pscustomobject]@{
        Root     = $root
        LogsRoot = $logsRoot
    }
}

# Import UI helpers
Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1")  -Force
Import-Module (Join-Path $rootPath "src\UI\MainWindow.UI.psm1") -Force

# Initialise config and logging
$cfg = Initialize-QOTConfig -RootPath $rootPath

Set-QLogRoot -Root $cfg.LogsRoot
Start-QLogSession

Write-QLog "Intro starting. Root path: $rootPath"

# ---------------------------------------------------------
# Optional splash (bootstrap can handle splash instead)
# ---------------------------------------------------------
$splash = $null

if (-not $SkipSplash) {
    $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
    $splash     = New-QOTSplashWindow -Path $splashXaml

    Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
    Update-QOTSplashProgress -Window $splash -Value 5
    [void]$splash.Show()
}

function Set-IntroProgress {
    param(
        [int]$Value,
        [string]$Text
    )

    if ($splash) {
        if ($Text)  { Update-QOTSplashStatus   -Window $splash -Text $Text }
        if ($Value) { Update-QOTSplashProgress -Window $splash -Value $Value }

        try {
            $splash.Dispatcher.Invoke({ }, [System.Windows.Threading.DispatcherPriority]::Background)
        } catch { }
    }
}

# Real stage-based progress now
Set-IntroProgress -Value 25 -Text "Loading UI..."
Set-IntroProgress -Value 55 -Text "Initialising modules..."
Set-IntroProgress -Value 85 -Text "Starting app..."

Write-QLog "Closing splash and starting main window."

if ($splash) {
    Set-IntroProgress -Value 100 -Text "Ready."
    Start-Sleep -Milliseconds 150
    $splash.Close()
}

# Start the main window
Start-QOTMain -Mode "Normal"

Write-QLog "Intro completed."
