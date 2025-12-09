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

# -----------------------------------------------------------------------------
# Local bootstrap version of Initialize-QOTConfig
# This guarantees the function exists even if the module doesn't export it yet.
# -----------------------------------------------------------------------------
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

Start-QLogSession

Write-QLog "Intro starting. Root path: $rootPath"

# Create and show splash window
$splashXaml = Join-Path $rootPath "src\Intro\Splash.xaml"
$splash     = New-QOTSplashWindow -Path $splashXaml

Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
Update-QOTSplashProgress -Window $splash -Value 10

[void]$splash.Show()

# Hand off to engine (this will open the main window)
Write-QLog "Calling Start-QOTMain from Intro."
Start-QOTMain -Mode "Normal"

Write-QLog "Intro completed."
