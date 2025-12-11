# MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit

Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force


# Keep references to the window and key controls inside this module
$script:MainWindow   = $null
$script:StatusLabel  = $null
$script:SummaryText  = $null
$script:MainProgress = $null
$script:RunButton    = $null

function New-QOTMainWindow {
    param(
        [string]$XamlPath
    )

    if (-not (Test-Path $XamlPath)) {
        throw "Main window XAML not found at path: $XamlPath"
    }

    Write-Verbose "Loading main window XAML from $XamlPath"

    # Load XAML into a WPF window
    $xamlText = Get-Content -Path $XamlPath -Raw
    $xml      = [xml]$xamlText
    $reader   = New-Object System.Xml.XmlNodeReader $xml
    $window   = [Windows.Markup.XamlReader]::Load($reader)

    # Set window icon from local icon.ico (fox icon)
    $iconPath = Join-Path $PSScriptRoot 'icon.ico'
    if (Test-Path $iconPath) {
        # Ensure WPF imaging types are available
        [void][Reflection.Assembly]::LoadWithPartialName("PresentationCore")

        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $bitmap.EndInit()

        $window.Icon = $bitmap
    }

    return $window
}

function Initialize-QOTMainWindow {
    # XAML lives in the same folder as this module
    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"

    $window = New-QOTMainWindow -XamlPath $xamlPath

    # Cache controls we care about
    $script:MainWindow   = $window
    $script:StatusLabel  = $window.FindName("StatusLabel")
    $script:SummaryText  = $window.FindName("SummaryText")
    $script:MainProgress = $window.FindName("MainProgress")
    $script:RunButton    = $window.FindName("RunButton")

    # Apps tab controls
    $BtnScanApps      = $window.FindName("BtnScanApps")
    $BtnUninstallApps = $window.FindName("BtnUninstallSelected")
    $AppsGrid         = $window.FindName("AppsGrid")
    $InstallGrid      = $window.FindName("InstallGrid")

    if ($BtnScanApps -and $BtnUninstallApps -and $AppsGrid -and $InstallGrid) {
        Initialize-QOTAppsUI -BtnScanApps $BtnScanApps `
                             -BtnUninstallSelected $BtnUninstallApps `
                             -AppsGrid $AppsGrid `
                             -InstallGrid $InstallGrid
    }


    # Simple initial state
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = "Idle"
    }

    if ($script:MainProgress) {
        $script:MainProgress.Minimum = 0
        $script:MainProgress.Maximum = 100
        $script:MainProgress.Value   = 0
    }

    # For now the Run button just updates the status text.
    # Later we will wire this into the engine.
    if ($script:RunButton -and $script:StatusLabel) {
        $script:RunButton.Add_Click({
            $script:StatusLabel.Text = "Run clicked (engine wiring coming soon)"
        })
    }

    return $script:MainWindow
}

function Start-QOTMainWindow {
    # Ensure the window is initialised
    $window = Initialize-QOTMainWindow

    try {
        # Make sure it sits on top of other windows while it is open
        $window.Topmost = $true
        [void]$window.ShowDialog()
    }
    finally {
        # Safety: if anything re-uses the window later, drop Topmost
        $window.Topmost = $false
    }
}
function Set-QOTStatus {
    param([string]$Text)

    if ($script:StatusLabel) {
        $script:StatusLabel.Dispatcher.Invoke({
            $script:StatusLabel.Text = $Text
        })
    }
}

function Set-QOTSummary {
    param([string]$Text)

    if ($script:SummaryText) {
        $script:SummaryText.Dispatcher.Invoke({
            $script:SummaryText.Text = $Text
        })
    }
}

Export-ModuleMember -Function `
    New-QOTMainWindow, `
    Initialize-QOTMainWindow, `
    Start-QOTMainWindow, `
    Set-QOTStatus, `
    Set-QOTSummary

