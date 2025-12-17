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
        if ($Control -is [System.Windows.Controls.TextBlock] -or
            $Control -is [System.Windows.Controls.TextBox]) {
            $Control.Text = $Value
            return
        }

        if ($Control -is [System.Windows.Controls.Label] -or
            $Control -is [System.Windows.Controls.ContentControl]) {
            $Control.Content = $Value
            return
        }

        if ($Control.PSObject.Properties.Name -contains 'Text') {
            $Control.Text = $Value
            return
        }
        if ($Control.PSObject.Properties.Name -contains 'Content') {
            $Control.Content = $Value
            return
        }
    }
    catch {
    }
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
                    -InstallGrid          $InstallGrid `
                    -RunButton            $script:RunButton
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
    param(
        [Parameter(Mandatory = $false)]
        [System.Windows.Window]$SplashWindow
    )

    try {
        $window = Initialize-QOTMainWindow

        if (-not $window) {
            throw "Initialize-QOTMainWindow returned null. Main window was not created."
        }

        if ($SplashWindow) {

            # When the main window has actually rendered, show Ready for 2s, fade, then close splash
            $window.Add_ContentRendered({

                try {
                    $SplashWindow.Dispatcher.Invoke([action]{

                        $bar = $SplashWindow.FindName("SplashProgressBar")
                        $txt = $SplashWindow.FindName("SplashStatusText")

                        if ($bar) { $bar.Value = 100 }
                        if ($txt) { $txt.Text  = "Ready" }

                    }, [System.Windows.Threading.DispatcherPriority]::Background)
                } catch { }

                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromSeconds(2)

                $timer.Add_Tick({
                    $timer.Stop()

                    try {
                        $SplashWindow.Dispatcher.Invoke([action]{
                            $SplashWindow.Topmost = $false

                            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                            $anim.From = 1
                            $anim.To = 0
                            $anim.Duration = [TimeSpan]::FromMilliseconds(300)

                            $SplashWindow.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
                        })
                    } catch { }

                    Start-Sleep -Milliseconds 330

                    try { $SplashWindow.Dispatcher.Invoke([action]{ $SplashWindow.Close() }) } catch { }
                })

                $timer.Start()
            })
        }

        # THIS is the message pump that makes WPF usable from PowerShell
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

    $icon = $BtnSettings.Content -as [System.Windows.Controls.TextBlock]
    if ($icon) { $icon.Text = [char]0xE72B }

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

    $icon = $BtnSettings.Content -as [System.Windows.Controls.TextBlock]
    if ($icon) { $icon.Text = [char]0xE713 }

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
