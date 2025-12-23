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
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")    -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1")  -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Settings.psm1")         -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")          -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # UI modules (hard reload to avoid ghost handlers)
    # ------------------------------------------------------------

    # Remove old exported functions just in case they were left behind
    Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue
    Remove-Item Function:\New-QOTSettingsView   -ErrorAction SilentlyContinue
    Remove-Item Function:\Initialize-QOTAppsUI  -ErrorAction SilentlyContinue

    # Unload by module name first (more reliable), then by path fallback
    Get-Module -Name "Tickets.UI" -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Tickets\Tickets.UI.psm1" } | Remove-Module -Force -ErrorAction SilentlyContinue

    Get-Module -Name "Settings.UI" -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Core\Settings\Settings.UI.psm1" } | Remove-Module -Force -ErrorAction SilentlyContinue

    Get-Module -Name "Apps.UI" -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Apps\Apps.UI.psm1" } | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import UI modules
    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")         -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1")  -Force -ErrorAction Stop

    # Apps modules (UI + logic)
    Import-Module (Join-Path $basePath "Apps\InstalledApps.psm1")         -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Apps\InstallCommonApps.psm1")     -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1")               -Force -ErrorAction Stop

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
    # Initialise Settings UI (hosted in SettingsHost)
    # ------------------------------------------------------------
    $settingsHost = $window.FindName("SettingsHost")
    if (-not $settingsHost) {
        throw "SettingsHost not found. Check MainWindow.xaml contains: <ContentControl x:Name='SettingsHost' />"
    }

    try {
        $cmd = Get-Command New-QOTSettingsView -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "New-QOTSettingsView not found. Check Core\Settings\Settings.UI.psm1 exports it."
        }

        $settingsView = New-QOTSettingsView -Window $window
        if (-not $settingsView) { throw "Settings view returned null" }

        $settingsHost.Content = $settingsView
    }
    catch {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Settings failed to load.`r`n$($_.Exception.Message)"
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        $tb.Margin = "10"
        $settingsHost.Content = $tb
    }

    # ------------------------------------------------------------
    # Initialise Apps UI
    # ------------------------------------------------------------
    try {
        $cmdApps = Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue
        if (-not $cmdApps) {
            throw "Initialize-QOTAppsUI not found. Check Apps\Apps.UI.psm1 exports it."
        }

        # These names must match your MainWindow.xaml x:Name values
        $btnScanApps         = $window.FindName("BtnScanApps")
        $btnUninstallSelected = $window.FindName("BtnUninstallSelected")

        # Try a couple of common grid names, because your XAML might use different ones
        $appsGrid = $window.FindName("AppsGrid")
        if (-not $appsGrid) { $appsGrid = $window.FindName("InstalledAppsGrid") }

        $installGrid = $window.FindName("InstallGrid")
        if (-not $installGrid) { $installGrid = $window.FindName("CommonAppsGrid") }

        $runButton = $window.FindName("RunSelectedActionsButton")
        if (-not $runButton) { $runButton = $window.FindName("BtnRunSelectedActions") }
        if (-not $runButton) { $runButton = $window.FindName("BtnRun") }

        if (-not $appsGrid)    { throw "Apps grid not found. Expected x:Name 'AppsGrid' or 'InstalledAppsGrid'." }
        if (-not $installGrid) { throw "Install grid not found. Expected x:Name 'InstallGrid' or 'CommonAppsGrid'." }

        try {
            Write-QLog ("Apps UI wiring: BtnScanApps null={0}, BtnUninstallSelected null={1}, RunButton null={2}" -f `
                ($null -eq $btnScanApps), ($null -eq $btnUninstallSelected), ($null -eq $runButton)) "DEBUG"
        } catch { }

        Initialize-QOTAppsUI `
            -BtnScanApps $btnScanApps `
            -BtnUninstallSelected $btnUninstallSelected `
            -AppsGrid $appsGrid `
            -InstallGrid $installGrid `
            -RunButton $runButton
    }
    catch {
        try { Write-QLog ("Apps UI failed to load: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Gear icon switches to Settings tab (tab is hidden)
    # ------------------------------------------------------------
    $btnSettings = $window.FindName("BtnSettings")
    $tabs        = $window.FindName("MainTabControl")
    $tabSettings = $window.FindName("TabSettings")

    if ($btnSettings -and $tabs -and $tabSettings) {
        $btnSettings.Add_Click({
            $tabs.SelectedItem = $tabSettings
        })
    }

    # ------------------------------------------------------------
    # Close splash + show main window
    # ------------------------------------------------------------
    try { if ($SplashWindow) { $SplashWindow.Close() } } catch { }
    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Start-QOTMainWindow
