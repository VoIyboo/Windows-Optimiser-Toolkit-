# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

function Get-QOTNamedElementsMap {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root
    )

    $map = @{}

    try {
        $q = New-Object 'System.Collections.Generic.Queue[System.Windows.DependencyObject]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()

            if ($cur -is [System.Windows.FrameworkElement]) {
                $n = $cur.Name
                if (-not [string]::IsNullOrWhiteSpace($n)) {
                    if (-not $map.ContainsKey($n)) {
                        $map[$n] = $cur.GetType().FullName
                    }
                }
            }

            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }

            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    } catch { }

    return $map
}

function Find-QOTElementByName {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        $q = New-Object 'System.Collections.Generic.Queue[System.Windows.DependencyObject]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()

            if ($cur -is [System.Windows.FrameworkElement]) {
                if ($cur.Name -eq $Name) { return $cur }
            }

            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }

            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    } catch { }

    return $null
}

function Ensure-QOTWindowName {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        $existing = $Window.FindName($Name)
        if ($existing) { return $existing }

        $found = Find-QOTElementByName -Root $Window -Name $Name
        if (-not $found) { return $null }

        # Register into window NameScope so Window.FindName starts working
        try {
            $Window.RegisterName($Name, $found)
        } catch { }

        return $found
    } catch {
        return $null
    }
}

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

    try { Write-QLog ("Loading XAML from: {0}" -f $xamlPath) "DEBUG" } catch { }

    $xaml   = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    # ------------------------------------------------------------
    # Optional: log key names present in LOADED XAML (helps catch mismatches)
    # ------------------------------------------------------------
    try {
        $map = Get-QOTNamedElementsMap -Root $window

        $wanted = @(
            "AppsGrid","InstallGrid","BtnScanApps","BtnUninstallSelected","RunButton",
            "SettingsHost","BtnSettings","MainTabControl","TabSettings",
            "TicketsGrid","BtnRefreshTickets","BtnNewTicket","BtnDeleteTicket"
        )

        foreach ($k in $wanted) {
            if ($map.ContainsKey($k)) {
                Write-QLog ("Found control: {0} ({1})" -f $k, $map[$k]) "DEBUG"
            } else {
                Write-QLog ("Missing control in loaded XAML: {0}" -f $k) "DEBUG"
            }
        }
    } catch { }

    # ------------------------------------------------------------
    # Ensure Tickets controls are registered into Window NameScope
    # (Fixes Window.FindName returning null for elements inside tab/template scopes)
    # ------------------------------------------------------------
    try {
        $tg  = Ensure-QOTWindowName -Window $window -Name "TicketsGrid"
        $br  = Ensure-QOTWindowName -Window $window -Name "BtnRefreshTickets"
        $bn  = Ensure-QOTWindowName -Window $window -Name "BtnNewTicket"
        $bd  = Ensure-QOTWindowName -Window $window -Name "BtnDeleteTicket"

        if (-not $tg) { try { Write-QLog "TicketsGrid could not be found in visual tree." "WARN" } catch { } }
        if (-not $br) { try { Write-QLog "BtnRefreshTickets could not be found in visual tree." "WARN" } catch { } }
        if (-not $bn) { try { Write-QLog "BtnNewTicket could not be found in visual tree." "WARN" } catch { } }
        if (-not $bd) { try { Write-QLog "BtnDeleteTicket could not be found in visual tree." "WARN" } catch { } }
    } catch { }

    # ------------------------------------------------------------
    # Initialise Tickets UI
    # ------------------------------------------------------------
    if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
        try { Initialize-QOTicketsUI -Window $window } catch { }
    }

    # ------------------------------------------------------------
    # Initialise Apps UI
    # ------------------------------------------------------------
    try {
        if (-not (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTAppsUI not found. Apps\Apps.UI.psm1 did not load or export correctly."
        }

        Initialize-QOTAppsUI -Window $window
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
