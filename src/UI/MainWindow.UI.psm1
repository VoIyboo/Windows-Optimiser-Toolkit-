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
    # Apps modules (data + engine)
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Apps\InstalledApps.psm1")      -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Apps\InstallCommonApps.psm1")  -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # UI modules (hard reload to avoid ghost handlers)
    # ------------------------------------------------------------
    Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue
    Remove-Item Function:\New-QOTSettingsView   -ErrorAction SilentlyContinue
    Remove-Item Function:\Initialize-QOTAppsUI  -ErrorAction SilentlyContinue

    Get-Module -Name "Tickets.UI"   -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name "Settings.UI"  -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name "Apps.UI"      -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue

    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Tickets\Tickets.UI.psm1" }            | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Core\Settings\Settings.UI.psm1" }     | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Apps\Apps.UI.psm1" }                  | Remove-Module -Force -ErrorAction SilentlyContinue

    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")         -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1")  -Force -ErrorAction Stop
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
        # Initialise Apps UI (wire to CURRENT XAML names)
        # ------------------------------------------------------------
        try {
            function Get-QOTNamedElements {
                param([Parameter(Mandatory)]$Root)
    
                $names = New-Object System.Collections.Generic.List[string]
    
                $walk = {
                    param($d)
                    if ($null -eq $d) { return }
                    try {
                        if ($d -is [System.Windows.FrameworkElement] -and -not [string]::IsNullOrWhiteSpace($d.Name)) {
                            [void]$names.Add($d.Name)
                        }
                    } catch { }
    
                    $count = 0
                    try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($d) } catch { $count = 0 }
    
                    for ($i = 0; $i -lt $count; $i++) {
                        $child = $null
                        try { $child = [System.Windows.Media.VisualTreeHelper]::GetChild($d, $i) } catch { $child = $null }
                        & $walk $child
                    }
                }
    
                & $walk $Root
                return ($names | Sort-Object -Unique)
            }
    
            $appsGrid        = $window.FindName("AppsGrid")
            $installGrid     = $window.FindName("InstallGrid")
            $btnScanApps     = $window.FindName("BtnScanApps")
            $btnUninstallSel = $window.FindName("BtnUninstallSelected")
            $btnRun          = $window.FindName("RunButton")
    
            if (-not $appsGrid -or -not $installGrid -or -not $btnRun) {
                $found = Get-QOTNamedElements -Root $window
                try { Write-QLog ("Apps UI binding failed. Expected names: AppsGrid, InstallGrid, RunButton. Found: {0}" -f ($found -join ", ")) "ERROR" } catch { }
    
                if (-not $appsGrid)    { throw "AppsGrid not found in MainWindow. Ensure the installed apps DataGrid has x:Name='AppsGrid'." }
                if (-not $installGrid) { throw "InstallGrid not found in MainWindow. Ensure the common apps DataGrid has x:Name='InstallGrid'." }
                if (-not $btnRun)      { throw "RunButton not found in MainWindow. Ensure the Run button has x:Name='RunButton'." }
            }
    
            if (-not (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTAppsUI not found. Apps\Apps.UI.psm1 did not load or export correctly."
            }
    
            Initialize-QOTAppsUI `
                -BtnScanApps $btnScanApps `
                -BtnUninstallSelected $btnUninstallSel `
                -AppsGrid $appsGrid `
                -InstallGrid $installGrid `
                -RunButton $btnRun
        }
        catch {
            try { Write-QLog ("Apps UI failed to load: {0}" -f $_.Exception.Message) "ERROR" } catch { }
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
