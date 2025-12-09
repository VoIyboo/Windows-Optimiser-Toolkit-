# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Make sure WPF assemblies are available
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Work out repo root:
#   src\Intro  -> parent = src
#   src        -> parent = repo root
$rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Paths to core modules
$configModule  = Join-Path $rootPath "src\Core\Config\Config.psm1"
$loggingModule = Join-Path $rootPath "src\Core\Logging\Logging.psm1"
$engineModule  = Join-Path $rootPath "src\Core\Engine\Engine.psm1"

# Import core modules (even if they don't currently export Init)
Import-Module $configModule  -Force
Import-Module $loggingModule -Force
Import-Module $engineModule  -Force

# -------------------------------------------------------------------
# Safety net: ensure logging functions exist, even if module is older
# -------------------------------------------------------------------
if (-not (Get-Command Set-QLogRoot -ErrorAction SilentlyContinue)) {
    function Set-QLogRoot {
        param([string]$Root)
        # Simple fallback: just remember the root in a global variable
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
# This guarantees the function exists even if the module doesn't
# export it yet.
# -------------------------------------------------------------------
function Initialize-QOTConfig {
    param(
        [string]$RootPath
    )

    # Decide root
    $root = if ($RootPath) { $RootPath } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }

    # Save globally so other modules can reuse it if they want
    $Global:QOTRoot = $root

    # ProgramData base + Logs folder
    $programDataRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit"
    $logsRoot        = Join-Path $programDataRoot "Logs"

    foreach ($path in @($programDataRoot, $logsRoot)) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }

    # Return a simple config object
    return [pscustomobject]@{
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

# Create and show splash window
$splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
$splash     = New-QOTSplashWindow -Path $splashXaml

Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
Update-QOTSplashProgress -Window $splash -Value 0

# Show the splash (non-modal so the script can keep running)
[void]$splash.Show()

# -----------------------------------------------------------------
# Drive the progress bar for up to ~10 seconds
# -----------------------------------------------------------------
$maxDurationMs = 10000          # 10 seconds
$steps         = 40             # number of progress updates
$stepDelayMs   = [int]($maxDurationMs / $steps)

for ($i = 1; $i -le $steps; $i++) {

    $percent = [int](($i / $steps) * 100)
    Update-QOTSplashProgress -Window $splash -Value $percent

    # Let the WPF dispatcher process animations / redraws
    try {
        $splash.Dispatcher.Invoke(
            { },
            [System.Windows.Threading.DispatcherPriority]::Background
        )
    } catch { }

    Start-Sleep -Milliseconds $stepDelayMs
}

# Ensure bar ends at 100%
Update-QOTSplashProgress -Window $splash -Value 100
Update-QOTSplashStatus   -Window $splash -Text "Ready."

Write-QLog "Splash finished. Closing splash and starting main window."

# Close the splash, then start the main window
$splash.Close()

Start-QOTMain -Mode "Normal"

Write-QLog "Intro completed."
