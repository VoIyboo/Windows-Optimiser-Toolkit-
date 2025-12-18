# MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit (Studio Voly Edition)

$ErrorActionPreference = "Stop"

$basePath = Join-Path $PSScriptRoot ".."

Import-Module (Join-Path $basePath "Core\Config\Config.psm1")   -Force -ErrorAction Stop
Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1") -Force -ErrorAction Stop

Import-Module (Join-Path $basePath "Core\Settings.psm1") -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $basePath "Core\Tickets.psm1")  -Force -ErrorAction SilentlyContinue

Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1") -Force -ErrorAction SilentlyContinue

Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue
Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")          -Force -ErrorAction Stop
Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1")   -Force -ErrorAction Stop

$script:IsSettingsShown = $false

$script:MainWindow   = $null
$script:StatusLabel  = $null
$script:SummaryText  = $null
$script:MainProgress = $null
$script:RunButton    = $null
$script:SettingsView = $null
$script:LastTab      = $null

function Set-QOTControlText {
    param(
        [Parameter(Mandatory)] $Control,
        [Parameter(Mandatory)] [string] $Value
    )

    if (-not $Control) { return }

    try {
        if ($Control -is [System.Windows.Controls.TextBlock] -or $Control -is [System.Windows.Controls.TextBox]) {
            $Control.Text = $Value
            return
        }

        if ($Control -is [System.Windows.Controls.Label] -or $Control -is [System.Windows.Controls.ContentControl]) {
            $Control.Content = $Value
            return
        }

        if ($Control.PSObject.Properties.Name -contains 'Text')    { $Control.Text    = $Value; return }
        if ($Control.PSObject.Properties.Name -contains 'Content') { $Control.Content = $Value; return }
    } catch { }
}

function New-QOTMainWindow {
    param(
        [Parameter(Mandatory)]
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

function Initialize-QOTMainWindow {
    try {
        $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
        $window   = New-QOTMainWindow -XamlPath $xamlPath

        if (-not $window) {
            throw "New-QOTMainWindow returned null."
        }

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
            } else {
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

        # Ensure we have a real WPF Application object
        $app = [System.Windows.Application]::Current
        if (-not $app) {
            $app = New-Object System.Windows.Application
            $app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
        }

        # Ensure WPF assemblies are loaded
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

        # Catch dispatcher exceptions and show real error
        try {
            $app.add_DispatcherUnhandledException({
                param($sender, $e)

                Write-Host ""
                Write-Host "================ WPF UNHANDLED EXCEPTION ================" -ForegroundColor Red
                Write-Host $e.Exception.ToString() -ForegroundColor Red
                Write-Host "========================================================" -ForegroundColor Red
                Write-Host ""

                $e.Handled = $true
            })
        } catch { }

        # Close splash AFTER main window is rendered
        if ($SplashWindow) {
            $window.Add_ContentRendered({

                try {
                    $bar = $SplashWindow.FindName("SplashProgressBar")
                    $txt = $SplashWindow.FindName("SplashStatusText")

                    if ($bar) { $bar.Value = 100 }
                    if ($txt) { $txt.Text  = "Ready" }

                    $timer = New-Object System.Windows.Threading.DispatcherTimer
                    $timer.Interval = [TimeSpan]::FromSeconds(2)
                    $timer.Add_Tick({
                        param($senderTimer, $eTimer)

                        try { if ($senderTimer) { $senderTimer.Stop() } } catch { }

                        try {
                            if ($SplashWindow) {
                                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                                $anim.From = 1
                                $anim.To = 0
                                $anim.Duration = [TimeSpan]::FromMilliseconds(300)
                                $SplashWindow.BeginAnimation(
                                    [System.Windows.Window]::OpacityProperty,
                                    $anim
                                )
                            }
                        } catch { }

                        $t2 = New-Object System.Windows.Threading.DispatcherTimer
                        $t2.Interval = [TimeSpan]::FromMilliseconds(330)
                        $t2.Add_Tick({
                            param($senderTimer2, $eTimer2)

                            try { if ($senderTimer2) { $senderTimer2.Stop() } } catch { }
                            try { if ($SplashWindow) { $SplashWindow.Close() } } catch { }
                        })
                        $t2.Start()
                    })
                    $timer.Start()
                }
                catch { }
            })
        }

        $Global:QOTMainWindow = $window
        $app.MainWindow = $window

        [void]$window.Show()
        [void]$app.Run()
    }
    catch {
        $msg = $_.Exception.Message
        try {
            if ($_.Exception.InnerException) {
                $msg += "`nInner: " + $_.Exception.InnerException.Message
            }
        } catch { }

        Write-Error "Start-QOTMainWindow : Failed to start Quinn Optimiser Toolkit UI.`n$msg"
        throw
    }
}


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

function Show-QOTSettingsPage {
    try {
        if (-not $script:MainWindow) { return }

        $host = $script:MainWindow.FindName("MainContentHost")
        if (-not $host) { return }

        # Save the TabControl once so we can restore it later
        if (-not $script:TabControl) {
            $script:TabControl = $script:MainWindow.FindName("MainTabControl")
        }

        if ($script:TabControl) {
            $script:LastTab = $script:TabControl.SelectedItem
        }

        # Build the settings view once
        if (-not $script:SettingsView) {

            if (Get-Command New-QOTSettingsView -ErrorAction SilentlyContinue) {
                $script:SettingsView = New-QOTSettingsView
            }
            elseif (Get-Command Get-QOTSettingsView -ErrorAction SilentlyContinue) {
                $script:SettingsView = Get-QOTSettingsView
            }
            else {
                # Placeholder panel (so the button visibly works right now)
                $grid = New-Object System.Windows.Controls.Grid
                $grid.Margin = "16"

                $title = New-Object System.Windows.Controls.TextBlock
                $title.Text = "Settings"
                $title.FontSize = 22
                $title.Foreground = [System.Windows.Media.Brushes]::White
                $title.Margin = "0,0,0,12"

                $hint = New-Object System.Windows.Controls.TextBlock
                $hint.Text = "Settings UI not wired yet. This is a placeholder panel."
                $hint.Foreground = [System.Windows.Media.Brushes]::Gainsboro
                $hint.TextWrapping = "Wrap"
                $hint.Margin = "0,40,0,0"

                $grid.Children.Add($title) | Out-Null
                $grid.Children.Add($hint)  | Out-Null

                $script:SettingsView = $grid
            }
        }

        # Swap content
        $host.Content = $script:SettingsView

        $script:IsSettingsShown = $true
        Set-QOTStatus "Settings"
    }
    catch {
        try { Set-QOTStatus "Settings error" } catch { }
        throw
    }
}

function Restore-QOTMainTabs {
    try {
        if (-not $script:MainWindow) { return }

        $host = $script:MainWindow.FindName("MainContentHost")
        if (-not $host) { return }

        if (-not $script:TabControl) {
            $script:TabControl = $script:MainWindow.FindName("MainTabControl")
        }

        if ($script:TabControl) {
            $host.Content = $script:TabControl

            if ($script:LastTab) {
                $script:TabControl.SelectedItem = $script:LastTab
            }
        }

        $script:IsSettingsShown = $false
        Set-QOTStatus "Idle"
    }
    catch {
        try { Set-QOTStatus "Restore error" } catch { }
        throw
    }
}

Export-ModuleMember -Function `
    Set-QOTControlText, `
    New-QOTMainWindow, `
    Initialize-QOTMainWindow, `
    Start-QOTMainWindow, `
    Select-QOTPreferredTab, `
    Set-QOTStatus, `
    Set-QOTSummary, `
    Show-QOTSettingsPage, `
    Restore-QOTMainTabs
