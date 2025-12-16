# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit

param(
    [switch]$SkipSplash,
    [string]$LogPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# ------------------------------
# Logging setup
# ------------------------------
if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogPath = Join-Path $logDir ("QOT_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

$script:QOTLogPath = $LogPath

# Silence noisy module import warnings (unapproved verbs etc.)
$oldWarningPreference = $WarningPreference
$WarningPreference = 'SilentlyContinue'

# ------------------------------
# WPF assemblies
# ------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Work out repo root:
# Work out repo root:
$rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Paths to core modules
$configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
$loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
$engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

# Import core modules (best effort)
if (Test-Path -LiteralPath $configModule)  { Import-Module $configModule  -Force -ErrorAction SilentlyContinue }
if (Test-Path -LiteralPath $loggingModule) { Import-Module $loggingModule -Force -ErrorAction SilentlyContinue }
if (Test-Path -LiteralPath $engineModule)  { Import-Module $engineModule  -Force -ErrorAction SilentlyContinue }

# ------------------------------
# Safety net logging fallbacks
# ------------------------------
if (-not (Get-Command Write-QLog -ErrorAction SilentlyContinue)) {
    function Write-QLog {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )

        $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] $Message"

        try {
            if ($script:QOTLogPath) {
                $line | Add-Content -Path $script:QOTLogPath -Encoding UTF8
            }
        } catch { }

        if (-not $Quiet) { Write-Host $line }
    }
}

if (-not (Get-Command Set-QLogRoot -ErrorAction SilentlyContinue)) {
    function Set-QLogRoot {
        param([string]$Root)
        $Global:QOTLogRoot = $Root
        Write-QLog "Set-QLogRoot fallback: $Root" "INFO"
    }
}

if (-not (Get-Command Start-QLogSession -ErrorAction SilentlyContinue)) {
    function Start-QLogSession {
        param([string]$Prefix = "QuinnOptimiserToolkit")
        Write-QLog "Log session started (fallback in Intro.ps1)." "INFO"
    }
}

# ------------------------------
# Local fallback config init
# ------------------------------
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
Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1")  -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $rootPath "src\UI\MainWindow.UI.psm1") -Force -ErrorAction SilentlyContinue

# Initialise config and logging
$cfg = Initialize-QOTConfig -RootPath $rootPath
Set-QLogRoot -Root $cfg.LogsRoot
Start-QLogSession

Write-QLog "Intro starting. Root path: $rootPath" "INFO"

# ------------------------------
# Optional splash
# ------------------------------
$splash = $null
$script:MinSplashMs   = 3000
$script:SplashShownAt = $null

if (-not $SkipSplash) {
    $splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
    $splash     = New-QOTSplashWindow -Path $splashXaml

    Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
    Update-QOTSplashProgress -Window $splash -Value 5
    [void]$splash.Show()

    $script:SplashShownAt = Get-Date
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

# Real stage-based progress
Set-IntroProgress -Value 25 -Text "Loading UI..."
Set-IntroProgress -Value 55 -Text "Initialising modules..."
Set-IntroProgress -Value 85 -Text "Starting app..."

Write-QLog "Closing splash and starting main window." "INFO"

if ($splash) {
    Set-IntroProgress -Value 100 -Text "Ready."

    $elapsedMs = 0
    if ($script:SplashShownAt) {
        $elapsedMs = [int]((Get-Date) - $script:SplashShownAt).TotalMilliseconds
    }

    if ($script:MinSplashMs -and $elapsedMs -lt $script:MinSplashMs) {
        Start-Sleep -Milliseconds ($script:MinSplashMs - $elapsedMs)
    }

    $splash.Close()
}

# Start the main window
Start-QOTMain -Mode "Normal"

Write-QLog "Intro completed." "INFO"

# Restore warning preference
$WarningPreference = $oldWarningPreference

if (-not $Quiet) {
    Write-Host "Log saved to: $script:QOTLogPath"
}
