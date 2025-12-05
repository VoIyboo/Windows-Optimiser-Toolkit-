Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

# Root folder for modules
$root = Split-Path $PSScriptRoot -Parent

# Import shared functions
Import-Module (Join-Path $root "Modules\QOT.Common.psm1") -Force

Initialize-QOTCommon
Write-Log "===== Quinn Optimiser Toolkit V3 starting UI ====="

# Load XAML
$xamlPath = Join-Path $PSScriptRoot "QOT.MainWindow.xaml"
if (-not (Test-Path $xamlPath)) {
    Write-Log "XAML file not found at $xamlPath" "ERROR"
    throw "Cannot start UI: XAML file missing."
}

$xaml = Get-Content $xamlPath -Raw

# Parse window
$window = [Windows.Markup.XamlReader]::Parse($xaml)

# Bind WPF controls so Set-Status works
$script:StatusLabel          = $window.FindName("StatusLabel")
$script:MainProgress         = $window.FindName("MainProgress")
$script:RunButton            = $window.FindName("RunButton")
$script:BtnScanApps          = $window.FindName("BtnScanApps")
$script:BtnUninstallSelected = $window.FindName("BtnUninstallSelected")

# Summary section
$SummaryText = $window.FindName("SummaryText")
$SummaryText.Text = Get-SystemSummaryText

# Load app logic module
Import-Module (Join-Path $root "Modules\QOT.Apps.psm1") -Force

# Wire buttons to the app logic
$BtnScanApps.Add_Click({
    Write-Log "User triggered app rescan"
    Refresh-InstalledApps
})

$BtnUninstallSelected.Add_Click({
    Write-Log "User triggered uninstall batch"
    Invoke-QOTAppUninstall
})

# Run actions
$RunButton.Add_Click({
    Write-Log "User pressed Run"
    Invoke-QOTActions
})

# Finally show the UI
$null = $window.ShowDialog()
Write-Log "===== Quinn Optimiser Toolkit V3 UI closed ====="
