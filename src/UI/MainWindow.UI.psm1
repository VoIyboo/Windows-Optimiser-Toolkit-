# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

function Start-QOTMainWindow {
    param([Parameter(Mandatory)]$SplashWindow)

    $basePath = Join-Path $PSScriptRoot ".."

    # Core
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force
    Import-Module (Join-Path $basePath "Core\Settings.psm1")        -Force
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")         -Force

    # UI
    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")   -Force
    Import-Module (Join-Path $basePath "Core\Settings.UI.psm1")     -Force

    # Load XAML
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    $xaml     = Get-Content $xamlPath -Raw
    $reader   = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window   = [System.Windows.Markup.XamlReader]::Load($reader)

    # Init Tickets
    if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
        Initialize-QOTicketsUI -Window $window
    }

    # Settings gear
    $btnSettings = $window.FindName("BtnSettings")
    if ($btnSettings) {
        $btnSettings.Add_Click({
            $content = New-QOTSettingsView
            $sw = New-Object System.Windows.Window
            $sw.Title = "Settings"
            $sw.Width = 520
            $sw.Height = 360
            $sw.Owner = $window
            $sw.Content = $content
            $sw.WindowStartupLocation = "CenterOwner"
            $sw.ShowDialog() | Out-Null
        })
    }

    try { $SplashWindow.Close() } catch {}
    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Start-QOTMainWindow
