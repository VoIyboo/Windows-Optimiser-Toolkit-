# Intro.ps1
# Minimal splash startup for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Make sure WPF assemblies are available
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Import core helpers
Import-Module "src\Core\Config.psm1"   -Force
Import-Module "src\Core\Logging.psm1" -Force
Import-Module "src\Intro\Splash.UI.psm1" -Force

# Resolve paths
$rootPath    = Get-QOTRoot
$splashXaml  = Join-Path $rootPath "src\Intro\Splash.xaml"

Write-QLog "Intro starting. Splash XAML at: $splashXaml"

# Create the splash window
$splash = New-QOTSplashWindow -Path $splashXaml

# Set initial status and show it
Update-QOTSplashStatus   -Window $splash -Text "Starting Quinn Optimiser Toolkit..."
Update-QOTSplashProgress -Window $splash -Value 10

# ShowDialog keeps this script in control until the window is closed
# but we will drive a few updates first
[void]$splash.Show()

Start-Sleep -Milliseconds 400
Update-QOTSplashStatus   -Window $splash -Text "Preparing core modules..."
Update-QOTSplashProgress -Window $splash -Value 40

Start-Sleep -Milliseconds 400
Update-QOTSplashStatus   -Window $splash -Text "Getting things ready..."
Update-QOTSplashProgress -Window $splash -Value 75

Start-Sleep -Milliseconds 400
Update-QOTSplashStatus   -Window $splash -Text "Almost there..."
Update-QOTSplashProgress -Window $splash -Value 100

Start-Sleep -Milliseconds 300

# Later this is where we will open the main window
Write-QLog "Intro finished. (Main window hook will go here later)"

$splash.Close()

