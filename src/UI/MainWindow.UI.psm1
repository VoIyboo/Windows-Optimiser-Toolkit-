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
Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1")       -Force -ErrorAction SilentlyContinue

# IMPORTANT: If any earlier module (like Settings) defined Initialize-QOTicketsUI,
# remove it so the correct Tickets UI version can be loaded.
Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue

# Load Tickets UI from the correct location, and do not hide failures.
Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1") -Force -ErrorAction Stop

# Settings UI module
Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1") -Force -ErrorAction Stop

# -------------------------------------------------------------------
# WINDOW LEVEL REFERENCES
# -------------------------------------------------------------------

$script:MainWindow   = $null
$script:StatusLabel  = $null
$script:SummaryText  = $null
$script:MainProgress = $null
$script:RunButton    = $null


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

    $xamlText = Get-Content -LiteralPath $XamlPath -Raw
    $xml      = [xml]$xamlText
    $reader   = New-Object System.Xml.XmlNodeReader $xml
    $window   = [Windows.Markup.XamlReader]::Load($reader)

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


# -------------------------------------------------------------------
# INIT WINDOW + TABS
# -------------------------------------------------------------------

function Initialize-QOTMainWindow {

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    $window   = New-QOTMainWindow -XamlPath $xamlPath

    $script:MainWindow   = $window
    $script:StatusLabel  = $window.FindName("StatusLabel")
    $script:SummaryText  = $window.FindName("SummaryText")
    $script:MainProgress = $window.FindName("MainProgress")
    $script:RunButton    = $window.FindName("RunButton")

    # ------------------------------
    # Apps Tab
    # ------------------------------
    $BtnScanApps        = $window.FindName("BtnScanApps")
    $BtnUninstallApps   = $window.FindName("BtnUninstallSelected")
    $AppsGrid           = $window.FindName("AppsGrid")
    $InstallGrid        = $window.FindName("InstallGrid")

    if (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue) {
        if ($BtnScanApps -and $BtnUninstallApps -and $AppsGrid -and $InstallGrid) {
            Initialize-QOTAppsUI `
                -BtnScanApps          $BtnScanApps `
                -BtnUninstallSelected $BtnUninstallApps `
                -AppsGrid             $AppsGrid `
                -InstallGrid          $InstallGrid
        }
    }

    # ------------------------------
    # Tickets Tab
    # ------------------------------
    $TicketsGrid       = $window.FindName("TicketsGrid")
    $BtnNewTicket      = $window.FindName("BtnNewTicket")
    $BtnRefreshTickets = $window.FindName("BtnRefreshTickets")
    $BtnDeleteTicket   = $window.FindName("BtnDeleteTicket")

    if (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue) {
        if ($TicketsGrid -and $BtnNewTicket -and $BtnRefreshTickets) {
            Initialize-QOTicketsUI `
                -TicketsGrid       $TicketsGrid `
                -BtnRefreshTickets $BtnRefreshTickets `
                -BtnNewTicket      $BtnNewTicket `
                -BtnDeleteTicket   $BtnDeleteTicket
        }
    }

    # ------------------------------
    # Settings init (safe)
    # ------------------------------
    if (-not $global:QOSettings) {
        if (Get-Command Get-QOSettings -ErrorAction SilentlyContinue) {
            $global:QOSettings = Get-QOSettings
        }
        else {
            $global:QOSettings = [pscustomobject]@{ PreferredStartTab = "Cleaning" }
        }
    }

    # ------------------------------
    # Ticket storage init (safe)
    # ------------------------------
    if (Get-Command Initialize-QOTicketStorage -ErrorAction SilentlyContinue) {
        Initialize-QOTicketStorage
    }
    elseif (Get-Command Initialize-QOTicketsStore -ErrorAction SilentlyContinue) {
        Initialize-QOTicketsStore
    }

    # Apply preferred start tab
    Select-QOTPreferredTab -PreferredTab $global:QOSettings.PreferredStartTab

    # ------------------------------
    # Status bar defaults
    # ------------------------------
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = "Idle"
    }

    if ($script:MainProgress) {
        $script:MainProgress.Minimum = 0
        $script:MainProgress.Maximum = 100
        $script:MainProgress.Value   = 0
    }

    # ------------------------------
    # Run button placeholder
    # ------------------------------
    if ($script:RunButton -and $script:StatusLabel) {
        $script:RunButton.Add_Click({
            $script:StatusLabel.Text = "Run clicked (engine coming soon)"
        })
    }

    return $script:MainWindow
}


# -------------------------------------------------------------------
# SHOW WINDOW
# -------------------------------------------------------------------

function Start-QOTMainWindow {

    $window = Initialize-QOTMainWindow
    [void]$window.ShowDialog()
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
    param(
        [string]$Text
    )

    if ($script:StatusLabel) {
        $script:StatusLabel.Dispatcher.Invoke({
            $script:StatusLabel.Text = $Text
        })
    }
}

function Set-QOTSummary {
    param(
        [string]$Text
    )

    if ($script:SummaryText) {
        $script:SummaryText.Dispatcher.Invoke({
            $script:SummaryText.Text = $Text
        })
    }
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
    Set-QOTSummary
