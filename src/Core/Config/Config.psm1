# Intro.ps1
# Entry point after bootstrap downloads the toolkit.
# Responsible for:
#   - Loading core modules (Config, Logging, Engine)
#   - Initialising config + logging
#   - Showing the splash screen, then the main window

param()

# Make sure WPF assemblies are available
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

# ------------------------------
# Import core modules
# ------------------------------
Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force
Import-Module "$PSScriptRoot\..\Core\Engine\Engine.psm1"   -Force

# ------------------------------
# Initialise config
# ------------------------------
# bootstrap.ps1 sets $Global:QOT_Root to the extracted repo root.
# If it exists, pass it in. Otherwise let Config auto-detect.
if ($Global:QOT_Root) {
    $config = Initialize-QOTConfig -RootPath $Global:QOT_Root
}
else {
    $config = Initialize-QOTConfig
}

# Point logging at the configured logs root
if ($config -and $config.LogsRoot) {
    Set-QLogRoot -Root $config.LogsRoot
}

Write-QLog "Intro.ps1 started. RootPath = $($config.RootPath)"

# ------------------------------
# Import splash + main window UI modules
# ------------------------------
Import-Module "$PSScriptRoot\Splash\Splash.UI.psm1"        -Force
Import-Module "$PSScriptRoot\..\UI\MainWindow.UI.psm1"     -Force

# ------------------------------
# Start the app flow
# ------------------------------
try {
    # Show splash, let it hand off to the main window when ready
    Show-QOTSplash
}
catch {
    Write-QLog "Error in Intro.ps1: $($_.Exception.Message)" "ERROR"
    [System.Windows.MessageBox]::Show(
        "Quinn Optimiser Toolkit failed to start:`n`n$($_.Exception.Message)",
        "Quinn Optimiser Toolkit",
        'OK',
        'Error'
    ) | Out-Null
}
