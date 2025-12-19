# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

function Start-QOTMainWindow {
    param(
        [Parameter(Mandatory)]
        $SplashWindow
    )

    $basePath = Join-Path $PSScriptRoot ".."

    # ------------------------------------------------------------
    # Core modules
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Settings.psm1")        -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")         -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # UI modules
    # ------------------------------------------------------------
    # Settings UI (force hard reload by path)
    $settingsUiPath = Join-Path $basePath "Core\Settings\Settings.UI.psm1"
    
    # Unload module if already loaded (by path)
    Get-Module | Where-Object { $_.Path -eq $settingsUiPath } | Remove-Module -Force -ErrorAction SilentlyContinue
    
    # Also clear any lingering functions
    Remove-Item Function:\New-QOTSettingsView     -ErrorAction SilentlyContinue
    Remove-Item Function:\Initialize-QOSettingsUI -ErrorAction SilentlyContinue
    Remove-Item Function:\Show-QOTSettingsWindow  -ErrorAction SilentlyContinue
    
    Import-Module $settingsUiPath -Force -ErrorAction Stop


    # ------------------------------------------------------------
    # Load MainWindow XAML
    # ------------------------------------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "MainWindow.xaml not found at $xamlPath"
    }

    $xaml   = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    # ------------------------------------------------------------
    # Initialise Tickets UI
    # ------------------------------------------------------------
    if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
        Initialize-QOTicketsUI -Window $window
    }

    # ------------------------------------------------------------
    # Initialise Settings UI (hosted in the hidden tab)
    # ------------------------------------------------------------
    $settingsHost = $window.FindName("SettingsHost")
    if (-not $settingsHost) {
        throw "SettingsHost not found. Check MainWindow.xaml contains: <ContentControl x:Name='SettingsHost' />"
    }

    $settingsView = $null

    if (Get-Command New-QOTSettingsView -ErrorAction SilentlyContinue) {
        $settingsView = New-QOTSettingsView -Window $window
    }
    elseif (Get-Command Initialize-QOSettingsUI -ErrorAction SilentlyContinue) {
        $settingsView = Initialize-QOSettingsUI -Window $window
    }
    else {
        throw "Settings UI entry function not found. Expected New-QOTSettingsView or Initialize-QOSettingsUI in Core\Settings\Settings.UI.psm1"
    }

    if (-not $settingsView) {
        throw "Settings UI returned null. Check Settings.UI.psm1 entry function returns a WPF element."
    }

    $settingsHost.Content = $settingsView

    # ------------------------------------------------------------
    # Gear icon switches to Settings tab (tab is hidden)
    # ------------------------------------------------------------
    $btnSettings = $window.FindName("BtnSettings")
    $tabs        = $window.FindName("MainTabControl")
    $tabSettings = $window.FindName("TabSettings")

    if (-not $btnSettings) { throw "BtnSettings not found in MainWindow.xaml" }
    if (-not $tabs)        { throw "MainTabControl not found in MainWindow.xaml" }
    if (-not $tabSettings) { throw "TabSettings not found in MainWindow.xaml" }

    $btnSettings.Add_Click({
        $tabs.SelectedItem = $tabSettings
    })

    # ------------------------------------------------------------
    # Close splash + show main window
    # ------------------------------------------------------------
    try { if ($SplashWindow) { $SplashWindow.Close() } } catch { }
    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Start-QOTMainWindow
