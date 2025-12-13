# MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit (Studio Voly Edition)

# -------------------------------------------------------------------
# CLEAN IMPORT BLOCK
# -------------------------------------------------------------------

Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"       -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1"     -Force
Import-Module "$PSScriptRoot\..\Core\Settings.psm1"            -Force
Import-Module "$PSScriptRoot\..\Core\Tickets.psm1"             -Force
Import-Module "$PSScriptRoot\..\Apps\Apps.UI.psm1"             -Force
Import-Module "$PSScriptRoot\..\Tickets\Tickets.UI.psm1"       -Force

# -------------------------------------------------------------------
# WINDOW-LEVEL GLOBAL REFERENCES
# -------------------------------------------------------------------

$script:MainWindow   = $null
$script:StatusLabel  = $null
$script:SummaryText  = $null
$script:MainProgress = $null
$script:RunButton    = $null

# -------------------------------------------------------------------
# LOAD XAML + ICON
# -------------------------------------------------------------------

function New-QOTMainWindow {
    param([string]$XamlPath)

    if (-not (Test-Path $XamlPath)) {
        throw "Main window XAML not found at: $XamlPath"
    }

    $xamlText = Get-Content -Path $XamlPath -Raw
    $xml      = [xml]$xamlText
    $reader   = New-Object System.Xml.XmlNodeReader $xml
    $window   = [Windows.Markup.XamlReader]::Load($reader)

    # Apply Studio Voly icon
    $iconPath = Join-Path $PSScriptRoot "icon.ico"
    if (Test-Path $iconPath) {

        [void][System.Reflection.Assembly]::LoadWithPartialName("PresentationCore")

        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $bmp.EndInit()

        $window.Icon = $bmp
    }

    return $window
}

# -------------------------------------------------------------------
# INITIALISE WINDOW + TABS
# -------------------------------------------------------------------

function Initialize-QOTMainWindow {

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    $window   = New-QOTMainWindow -XamlPath $xamlPath

    # Cache references
    $script:MainWindow   = $window
    $script:StatusLabel  = $window.FindName("StatusLabel")
    $script:SummaryText  = $window.FindName("SummaryText")
    $script:MainProgress = $window.FindName("MainProgress")
    $script:RunButton    = $window.FindName("RunButton")

    # ------------------------------
    # Apps Tab
    # ------------------------------
    $BtnScanApps      = $window.FindName("BtnScanApps")
    $BtnUninstallApps = $window.FindName("BtnUninstallSelected")
    $AppsGrid         = $window.FindName("AppsGrid")
    $InstallGrid      = $window.FindName("InstallGrid")

    if ($BtnScanApps -and $BtnUninstallApps -and $AppsGrid -and $InstallGrid) {
        Initialize-QOTAppsUI `
            -BtnScanApps        $BtnScanApps `
            -BtnUninstallSelected $BtnUninstallApps `
            -AppsGrid           $AppsGrid `
            -InstallGrid        $InstallGrid
    }

    # ------------------------------
    # Tickets Tab
    # ------------------------------
    $TicketsGrid       = $window.FindName("TicketsGrid")
    $BtnNewTicket      = $window.FindName("BtnNewTicket")
    $BtnRefreshTickets = $window.FindName("BtnRefreshTickets")
    $BtnDeleteTicket   = $window.FindName("BtnDeleteTicket")
    
    if ($TicketsGrid -and $BtnNewTicket -and $BtnRefreshTickets) {
    Initialize-QOTicketsUI `
        -TicketsGrid $TicketsGrid `
        -BtnRefreshTickets $BtnRefreshTickets `
        -BtnNewTicket $BtnNewTicket `
        -BtnDeleteTicket $BtnDeleteTicket
    }

    # ------------------------------
    # Settings + Ticket Storage Init
    # ------------------------------

    if (-not $global:QOSettings) {
        $global:QOSettings = Get-QOSettings
    }

    Initialize-QOTicketStorage   # Ensures Tickets.json + backups folder exist

    # Apply preferred start tab
    Select-QOTPreferredTab -PreferredTab $global:QOSettings.PreferredStartTab

    # ------------------------------
    # Status Bar Defaults
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
    # Run Button placeholder
    # ------------------------------

    if ($script:RunButton -and $script:StatusLabel) {
        $script:RunButton.Add_Click({
            $script:StatusLabel.Text = "Run clicked (engine coming soon)"
        })
    }

    return $script:MainWindow
}

# -------------------------------------------------------------------
# WINDOW DISPLAY
# -------------------------------------------------------------------

function Start-QOTMainWindow {

    $window = Initialize-QOTMainWindow

    try {
        $window.Topmost = $true
        [void]$window.ShowDialog()
    }
    finally {
        $window.Topmost = $false
    }
}

# -------------------------------------------------------------------
# TAB SELECTION
# -------------------------------------------------------------------

function Select-QOTPreferredTab {
    param([string]$PreferredTab)

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

# -------------------------------------------------------------------
# EXPORTS
# -------------------------------------------------------------------

Export-ModuleMember -Function `
    New-QOTMainWindow, `
    Initialize-QOTMainWindow, `
    Start-QOTMainWindow, `
    Set-QOTStatus, `
    Set-QOTSummary
