# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Make sure WPF assemblies are available
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Work out repo root:
# src\Intro  -> parent = src
# src        -> parent = repo root
$rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Import core modules using absolute paths from root
Import-Module (Join-Path $rootPath "src\Core\Config\Config.psm1")   -Force
Import-Module (Join-Path $rootPath "src\Core\Logging\Logging.psm1") -Force
Import-Module (Join-Path $rootPath "src\Core\Engine\Engine.psm1")   -Force

# Import UI helpers
Import-Module (Join-Path $rootPath "src\Intro\Splash.UI.psm1")      -Force
Import-Module (Join-Path $rootPath "src\UI\MainWindow.UI.psm1")     -Force

# Initialise config and logging
$cfg = Initialize-QOTConfig -RootPath $rootPath
Set-QLogRoot -Root $cfg.LogsRoot
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
