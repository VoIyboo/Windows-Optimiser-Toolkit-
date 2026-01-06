# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside MainWindow)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

# ------------------------------------------------------------
# Logger
# ------------------------------------------------------------
$script:QOLog = {
    param([string]$Message)
    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $path = Join-Path $logDir "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    } catch { }
}

function Write-QOSettingsUILog {
    param([string]$Message)
    & $script:QOLog $Message
}

Write-QOSettingsUILog "=== Settings.UI.psm1 LOADED ==="
try { Write-QOSettingsUILog ("Settings path = " + (Get-QOSettingsPath)) } catch { }

# ------------------------------------------------------------
# One time WPF assembly load
# ------------------------------------------------------------
$script:QOSettings_AssembliesLoaded = $false
function Initialize-QOSettingsUIAssemblies {
    if ($script:QOSettings_AssembliesLoaded) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    $script:QOSettings_AssembliesLoaded = $true
    Write-QOSettingsUILog "WPF assemblies loaded once"
}

# ------------------------------------------------------------
# Visual tree helpers
# ------------------------------------------------------------
function Find-QOElementByNameAndType {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [Type] $Type
    )

    function Walk {
        param($Parent)

        if ($null -eq $Parent) { return $null }

        try {
            if ($Parent -is $Type -and $Parent.Name -eq $Name) { return $Parent }
        } catch { }

        $count = 0
        try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent) }
        catch { return $null }

        for ($i = 0; $i -lt $count; $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
            $found = Walk $child
            if ($found) { return $found }
        }

        return $null
    }

    return (Walk $Root)
}

function Get-QOControl {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [Type] $Type
    )

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $c = $Root.FindName($Name)
            if ($c -and ($c -is $Type)) { return $c }
        }
    } catch { }

    return Find-QOElementByNameAndType -Root $Root -Name $Name -Type $Type
}

function Convert-SettingsWindowToHostableRoot {
    param([Parameter(Mandatory)][xml]$Doc)

    $win = $Doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") {
        throw "SettingsWindow.xaml root must be <Window>."
    }

    $ns   = $win.NamespaceURI
    $grid = $Doc.CreateElement("Grid", $ns)

    $removeAttrs = @(
        "Title","Height","Width","Topmost","WindowStartupLocation",
        "ResizeMode","SizeToContent","ShowInTaskbar","WindowStyle","AllowsTransparency"
    )

    foreach ($a in @($win.Attributes)) {
        if ($removeAttrs -contains $a.Name) { continue }
        $null = $grid.Attributes.Append($a.Clone())
    }

    foreach ($child in @($win.ChildNodes)) {
        if ($child.NodeType -ne "Element") { continue }

        if ($child.LocalName -eq "Window.Resources") {
            $newRes = $Doc.CreateElement("Grid.Resources", $ns)
            foreach ($rChild in @($child.ChildNodes)) {
                $null = $newRes.AppendChild($rChild.Clone())
            }
            $null = $grid.AppendChild($newRes)
        } else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $Doc.RemoveChild($win)
    $null = $Doc.AppendChild($grid)

    return $Doc
}

# ------------------------------------------------------------
# Stored handlers to avoid double wiring
# ------------------------------------------------------------
$script:QOSettings_AddHandler     = $null
$script:QOSettings_RemHandler     = $null
$script:QOSettings_CalHandler     = $null
$script:QOSettings_FollowHandler  = $null
$script:QOSettings_DateTimer      = $null

function New-QOTSettingsView {
    Initialize-QOSettingsUIAssemblies

    # Capture commands NOW, so the WPF handlers can always call them later
    $setMonitoredCmd = Get-Command Set-QOMonitoredAddresses -ErrorAction Stop
    $getSettingsCmd  = Get-Command Get-QOSettings -ErrorAction Stop

    $getDateStateCmd = Get-Command Get-QOEmailSyncStartDateState -ErrorAction Stop
    $pinDateCmd      = Get-Command Set-QOEmailSyncStartDatePinned -ErrorAction Stop
    $clearDateCmd    = Get-Command Clear-QOEmailSyncStartDatePinned -ErrorAction Stop

    $xamlPath = Join-Path $PSScriptRoot "SettingsWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "SettingsWindow.xaml not found at $xamlPath"
    }

    Write-QOSettingsUILog "Loading SettingsWindow.xaml (hosted)"

    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $doc = Convert-SettingsWindowToHostableRoot -Doc $doc

    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root   = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load Settings view from SettingsWindow.xaml" }

    # Controls
    $txtEmail = Get-QOControl -Root $root -Name "TxtEmail"      -Type ([System.Windows.Controls.TextBox])
    $btnAdd   = Get-QOControl -Root $root -Name "BtnAdd"        -Type ([System.Windows.Controls.Button])
    $btnRem   = Get-QOControl -Root $root -Name "BtnRemove"     -Type ([System.Windows.Controls.Button])
    $list     = Get-QOControl -Root $root -Name "LstEmails"     -Type ([System.Windows.Controls.ListBox])

    $cal      = Get-QOControl -Root $root -Name "CalEmailCutoff" -Type ([System.Windows.Controls.Calendar])
    $btnToday = Get-QOControl -Root $root -Name "BtnFollowToday" -Type ([System.Windows.Controls.Button])
    $hint     = Get-QOControl -Root $root -Name "LblHint"        -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }
    if (-not $cal)      { throw "CalEmailCutoff not found (Calendar)" }
    if (-not $btnToday) { throw "BtnFollowToday not found (Button)" }

    # -------------------------
    # Mailbox list binding
    # -------------------------
    $addresses = New-Object "System.Collections.ObjectModel.ObservableCollection[string]"
    $getMonitoredCmd = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction Stop

    foreach ($e in @(& $getMonitoredCmd)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }

    $list.ItemsSource = $addresses
    Write-QOSettingsUILog ("Bound mailbox list. Count=" + $addresses.Count)

    # Remove old handlers (if any)
    try { if ($script:QOSettings_AddHandler) { $btnAdd.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler) } } catch { }
    try { if ($script:QOSettings_RemHandler) { $btnRem.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler) } } catch { }

    $script:QOSettings_AddHandler = [System.Windows.RoutedEventHandler]{
        try {
            $addr = ([string]$txtEmail.Text).Trim()
            Write-QOSettingsUILog ("Add clicked. Input='" + $addr + "'")

            if (-not $addr) {
                if ($hint) { $hint.Text = "Enter an email address." }
                return
            }

            $lower = $addr.ToLower()
            foreach ($x in $addresses) {
                if (([string]$x).Trim().ToLower() -eq $lower) {
                    $txtEmail.Text = ""
                    if ($hint) { $hint.Text = "Already exists." }
                    return
                }
            }

            $addresses.Add($addr)
            $txtEmail.Text = ""

            $saveList = @($addresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $null = & $setMonitoredCmd -Addresses $saveList

            $after = & $getSettingsCmd
            $count = @($after.Tickets.EmailIntegration.MonitoredAddresses).Count
            Write-QOSettingsUILog ("Saved. Stored count=" + $count)

            if ($hint) { $hint.Text = "Added $addr" }
        }
        catch {
            Write-QOSettingsUILog ("Add failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Add stack: " + $_.ScriptStackTrace)
        }
    }.GetNewClosure()

    $script:QOSettings_RemHandler = [System.Windows.RoutedEventHandler]{
        try {
            $sel = $list.SelectedItem
            Write-QOSettingsUILog ("Remove clicked. Selected='" + ($sel + "") + "'")

            if (-not $sel) {
                if ($hint) { $hint.Text = "Select an address to remove." }
                return
            }

            [void]$addresses.Remove([string]$sel)

            $saveList = @($addresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $null = & $setMonitoredCmd -Addresses $saveList

            $after = & $getSettingsCmd
            $count = @($after.Tickets.EmailIntegration.MonitoredAddresses).Count
            Write-QOSettingsUILog ("Removed. Stored count=" + $count)

            if ($hint) { $hint.Text = "Removed $sel" }
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Remove stack: " + $_.ScriptStackTrace)
        }
    }.GetNewClosure()

    $btnAdd.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
    $btnRem.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)

    Write-QOSettingsUILog "Wired mailbox handlers using AddHandler"

    # -------------------------
    # Calendar: follow-today vs pinned date
    # -------------------------
    function Set-HintFromState {
        param($state)
        try {
            if (-not $hint) { return }
            if ($state.Pinned) {
                $hint.Text = ("Pinned start date: " + $state.Date.ToString("dd/MM/yyyy"))
            } else {
                $hint.Text = "Start date follows today until you select a date."
            }
        } catch { }
    }

    # Load date state
    try {
        $state = & $getDateStateCmd
        $cal.SelectedDate = $state.Date
        $cal.DisplayDate  = $state.Date
        Set-HintFromState -state $state
        Write-QOSettingsUILog ("Loaded date state. Pinned=" + $state.Pinned + " Date=" + $state.Date.ToString("yyyy-MM-dd"))
    } catch {
        Write-QOSettingsUILog ("Load date state failed: " + $_.Exception.ToString())
        if ($hint) { $hint.Text = "Date state failed to load. Check logs." }
    }

    # Remove old handlers
    try { if ($script:QOSettings_CalHandler) { $cal.RemoveHandler([System.Windows.Controls.Calendar]::SelectedDatesChangedEvent, $script:QOSettings_CalHandler) } } catch { }
    try { if ($script:QOSettings_FollowHandler) { $btnToday.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_FollowHandler) } } catch { }

    # Correct delegate type for Calendar SelectedDatesChanged
    $script:QOSettings_CalHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        try {
            $picked = $cal.SelectedDate
            if (-not $picked) { return }

            $picked = ([datetime]$picked).Date
            $null = & $pinDateCmd -Date $picked

            $state2 = & $getDateStateCmd
            Set-HintFromState -state $state2

            Write-QOSettingsUILog ("Pinned date selected: " + $picked.ToString("yyyy-MM-dd"))
        }
        catch {
            Write-QOSettingsUILog ("Calendar select failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Date select failed. Check logs." }
        }
    }.GetNewClosure()

    $cal.AddHandler([System.Windows.Controls.Calendar]::SelectedDatesChangedEvent, $script:QOSettings_CalHandler)

    $script:QOSettings_FollowHandler = [System.Windows.RoutedEventHandler]{
        try {
            $null = & $clearDateCmd

            $today = (Get-Date).Date
            $cal.SelectedDate = $today
            $cal.DisplayDate  = $today

            $state3 = & $getDateStateCmd
            Set-HintFromState -state $state3

            Write-QOSettingsUILog "Follow today pressed (unpinned)."
        }
        catch {
            Write-QOSettingsUILog ("Follow today failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Follow today failed. Check logs." }
        }
    }.GetNewClosure()

    $btnToday.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_FollowHandler)

    # Timer: if not pinned, keep following today's date (in case app stays open overnight)
    try {
        if (-not $script:QOSettings_DateTimer) {
            $script:QOSettings_DateTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:QOSettings_DateTimer.Interval = [TimeSpan]::FromMinutes(1)

            $script:QOSettings_DateTimer.Add_Tick({
                try {
                    $st = & $getDateStateCmd
                    if ($st.Pinned) { return }

                    $today = (Get-Date).Date
                    $cur = $cal.SelectedDate
                    if ($cur) { $cur = ([datetime]$cur).Date }

                    if (-not $cur -or $cur -ne $today) {
                        $cal.SelectedDate = $today
                        $cal.DisplayDate  = $today
                        Set-HintFromState -state $st
                    }
                } catch { }
            }) | Out-Null

            $script:QOSettings_DateTimer.Start()
            Write-QOSettingsUILog "Started follow-today timer (1 min)."
        }
    } catch {
        Write-QOSettingsUILog ("Timer init failed: " + $_.Exception.ToString())
    }

    Write-QOSettingsUILog "Wired calendar handlers using correct delegate types"

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
