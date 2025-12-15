# MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit (Studio Voly Edition)

$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# IMPORTS
# -------------------------------------------------------------------

$basePath = Join-Path $PSScriptRoot ".."

Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force -ErrorAction Stop
Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force -ErrorAction Stop

# Core modules can be soft if older builds do not include them
Import-Module (Join-Path $basePath "Core\Settings.psm1") -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $basePath "Core\Tickets.psm1")  -Force -ErrorAction SilentlyContinue

# UI modules
Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1") -Force -ErrorAction SilentlyContinue

# IMPORTANT: If any earlier module (like Settings) defined Initialize-QOTicketsUI,
# remove it so the correct Tickets UI version can be loaded.
Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue

# Load Tickets UI from the correct location
Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1") -Force -ErrorAction Stop

# Settings UI module
Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1") -Force -ErrorAction Stop

# -------------------------------------------------------------------
# WINDOW LEVEL REFERENCES
# -------------------------------------------------------------------

$script:IsSettingsShown = $false

$script:MainWindow   = $null
$script:StatusLabel  = $null
$script:SummaryText  = $null
$script:MainProgress = $null
$script:RunButton    = $null
$script:SettingsView = $null
$script:LastTab      = $null

# -------------------------------------------------------------------
# SAFE TEXT SETTER
# -------------------------------------------------------------------

function Set-QOTControlText {
    param(
        [Parameter(Mandatory)] $Control,
        [Parameter(Mandatory)] [string] $Value
    )

    if (-not $Control) { return }

    try {
        # Most common: TextBlock / TextBox
        if ($Control -is [System.Windows.Controls.TextBlock] -or
            $Control -is [System.Windows.Controls.TextBox]) {
            $Control.Text = $Value
            return
        }

        # Label + most WPF content controls
        if ($Control -is [System.Windows.Controls.Label] -or
            $Control -is [System.Windows.Controls.ContentControl]) {
            $Control.Content = $Value
            return
        }

        # Fallback: try Text, then Content
        $m = $Control | Get-Member -Name Text -MemberType Property -ErrorAction SilentlyContinue
        if ($m) {
            $Control.Text = $Value
            return
        }
    } catch {}

    try { $Control.Content = $Value } catch {}
}

# -------------------------------------------------------------------
# XAML LOADER
# -------------------------------------------------------------------

function New-QOTMainWindow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$XamlPath
    )

    if (-not (Test-Path -LiteralPath $XamlPath)) {
        throw "Main window XAML not found at: $XamlPath"
    }

    try {
        $xamlText = Get-Content -LiteralPath $XamlPath -Raw
        $xml      = [xml]$xamlText
        $reader   = New-Object System.Xml.XmlNodeReader $xml
        $window   = [Windows.Markup.XamlReader]::Load($reader)

        if (-not $window) {
            throw "XamlReader returned null (unknown XAML parse failure)."
        }

        # Apply Studio Voly icon (optional)
        $iconPath = Join-Path $PSScriptRoot "icon.ico"
        if (Test-Path -LiteralPath $iconPath) {
            Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue

            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.UriSource = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
            $bmp.EndInit()
            $window.Icon = $bmp
        }

        return $window
    }
    catch {
        throw "Failed to load MainWindow.xaml. $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------
# INIT WINDOW + TABS
# -------------------------------------------------------------------

function Initialize-QOTMainWindow {
    try {

        $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
        $window   = New-QOTMainWindow -XamlPath $xamlPath

        $script:MainWindow   = $window
        $script:StatusLabel  = $window.FindName("StatusLabel")
        $script:SummaryText  = $window.FindName("SummaryText")
        $script:MainProgress = $window.FindName("MainProgress")
        $script:RunButton    = $window.FindName("RunButton")

        # Apps Tab
        $BtnScanApps      = $window.FindName("BtnScanApps")
        $BtnUninstallApps = $window.FindName("BtnUninstallSelected")
        $AppsGrid         = $window.FindName("AppsGrid")
        $InstallGrid      = $window.FindName("InstallGrid")

        if (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue) {
            if ($BtnScanApps -and $BtnUninstallApps -and $AppsGrid -and $InstallGrid) {
                Initialize-QOTAppsUI `
                    -BtnScanApps          $BtnScanApps `
                    -BtnUninstallSelected $BtnUninstallApps `
                    -AppsGrid             $AppsGrid `
                    -InstallGrid          $InstallGrid
            }
        }

        # Tickets Tab
        $TicketsGrid       = $window.FindName("TicketsGrid")
        $BtnNewTicket      = $window.FindName("BtnNewTicket")
        $BtnRefreshTickets = $window.FindName("BtnRefreshTickets")
        $BtnDeleteTicket   = $window.FindName("BtnDeleteTicket")

        if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
            if ($TicketsGrid -and $BtnNewTicket -and $BtnRefreshTickets -and $BtnDeleteTicket) {
                Initialize-QOTicketsUI `
                    -TicketsGrid       $TicketsGrid `
                    -BtnRefreshTickets $BtnRefreshTickets `
                    -BtnNewTicket      $BtnNewTicket `
                    -BtnDeleteTicket   $BtnDeleteTicket
            }
        }

        # Settings button
        $BtnSettings = $window.FindName("BtnSettings")
        if ($BtnSettings) {
            $BtnSettings.Add_Click({
                if ($script:IsSettingsShown) { Restore-QOTMainTabs }
                else { Show-QOTSettingsPage }
            })
        }

        # Settings init
        if (-not $global:QOSettings) {
            if (Get-Command Get-QOSettings -ErrorAction SilentlyContinue) {
                $global:QOSettings = Get-QOSettings
            }
            else {
                $global:QOSettings = [pscustomobject]@{ PreferredStartTab = "Cleaning" }
            }
        }

        Select-QOTPreferredTab -PreferredTab $global:QOSettings.PreferredStartTab

        Set-QOTControlText -Control $script:StatusLabel -Value "Idle"

        if ($script:MainProgress) {
            $script:MainProgress.Minimum = 0
            $script:MainProgress.Maximum = 100
            $script:MainProgress.Value   = 0
        }

        if ($script:RunButton) {
            $script:RunButton.Add_Click({
                Set-QOTControlText -Control $script:StatusLabel -Value "Run clicked (engine coming soon)"
            })
        }

        return $window
    }
    catch {
        throw "Initialize-QOTMainWindow failed: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------
# SHOW WINDOW
# -------------------------------------------------------------------

function Start-QOTMainWindow {

    try {
        $window = Initialize-QOTMainWindow

        if (-not $window) {
            throw "Initialize-QOTMainWindow returned null. Main window was not created."
        }

        [void]$window.ShowDialog()
    }
    catch {
        Write-Error "Failed to start Quinn Optimiser Toolkit UI.`n$($_.Exception.Message)"
        throw
    }
}

# -------------------------------------------------------------------
# TAB SELECTION
# -------------------------------------------------------------------

function Select-QOTPreferredTab {
    param(
        [string]$PreferredTab
    )

    if (-not $script:MainWindow) { return }

    $tabControl = $script:MainWindow.FindName("MainTabControl")
    if (-not $tabControl) { return }

    $targetTab = switch ($PreferredTab) {
        'Cleaning' { $script:MainWindow.FindName("TabCleaning") }
        'Apps'     { $script:MainWindow.FindName("TabApps") }
        'Advanced' { $script:MainWindow.FindName("TabAdvanced") }
        'Tickets'  { $script:MainWindow.FindName("TabTickets") }
        default    { $script:MainWindow.FindName("TabCleaning") }
    }

    if ($targetTab -and $tabControl.Items.Contains($targetTab)) {
        $tabControl.SelectedItem = $targetTab
    }
    elseif ($tabControl.Items.Count -gt 0) {
        $tabControl.SelectedIndex = 0
    }
}

# -------------------------------------------------------------------
# STATUS + SUMMARY HELPERS
# -------------------------------------------------------------------

function Set-QOTStatus {
    param([string]$Text)

    if ($script:StatusLabel) {
        $script:StatusLabel.Dispatcher.Invoke({
            Set-QOTControlText -Control $script:StatusLabel -Value $Text
        })
    }
}

function Set-QOTSummary {
    param([string]$Text)

    if ($script:SummaryText) {
        $script:SummaryText.Dispatcher.Invoke({
            Set-QOTControlText -Control $script:SummaryText -Value $Text
        })
    }
}

# -------------------------------------------------------------------
# SETTINGS VIEW SWAP
# -------------------------------------------------------------------

function Show-QOTSettingsPage {
    if (-not $script:MainWindow) { return }

    $MainContentHost = $script:MainWindow.FindName("MainContentHost")
    $MainTabControl  = $script:MainWindow.FindName("MainTabControl")
    $BtnSettings     = $script:MainWindow.FindName("BtnSettings")

    if (-not $MainContentHost -or -not $MainTabControl -or -not $BtnSettings) { return }

    $script:LastTab = $MainTabControl.SelectedItem

    if (-not $script:SettingsView) {
        if (-not (Get-Command Initialize-QOSettingsUI -ErrorAction SilentlyContinue)) {
            Set-QOTStatus "Settings UI not available"
            return
        }
        $script:SettingsView = Initialize-QOSettingsUI -Window $script:MainWindow
    }

    $MainContentHost.Content = $script:SettingsView

    $icon = $script:MainWindow.FindName("BtnSettingsIcon")
    Set-QOTControlText -Control $icon -Value ([char]0xE72B)

    $BtnSettings.ToolTip = "Back"
    $script:IsSettingsShown = $true
    Set-QOTStatus "Settings"
}

function Restore-QOTMainTabs {
    if (-not $script:MainWindow) { return }

    $MainContentHost = $script:MainWindow.FindName("MainContentHost")
    $MainTabControl  = $script:MainWindow.FindName("MainTabControl")
    $BtnSettings     = $script:MainWindow.FindName("BtnSettings")

    if (-not $MainContentHost -or -not $MainTabControl -or -not $BtnSettings) { return }

    $MainContentHost.Content = $MainTabControl

    if ($script:LastTab) { $MainTabControl.SelectedItem = $script:LastTab }

    $icon = $script:MainWindow.FindName("BtnSettingsIcon")
    Set-QOTControlText -Control $icon -Value ([char]0xE713)

    $BtnSettings.ToolTip = "Settings"
    $script:IsSettingsShown = $false
    Set-QOTStatus "Idle"
}

# -------------------------------------------------------------------
# EXPORTS
# -------------------------------------------------------------------

Export-ModuleMember -Function `
    New-QOTMainWindow, `
    Initialize-QOTMainWindow, `
    Start-QOTMainWindow, `
    Select-QOTPreferredTab, `
    Set-QOTStatus, `
    Set-QOTSummary, `
    Show-QOTSettingsPage, `
    Restore-QOTMainTabs
