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
$script:QOSettings_AddClick = $null
$script:QOSettings_RemClick = $null
$script:QOSettings_FollowTodayClick = $null
$script:QOSettings_CalendarChanged = $null
$script:QOSettings_TodayTimer = $null

function Stop-QOSettingsTodayTimer {
    try {
        if ($script:QOSettings_TodayTimer) {
            $script:QOSettings_TodayTimer.Stop()
            $script:QOSettings_TodayTimer = $null
        }
    } catch { }
}

function Start-QOSettingsTodayTimer {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.Calendar]$Cal,
        [Parameter(Mandatory)][System.Windows.Controls.TextBlock]$Hint
    )

    Stop-QOSettingsTodayTimer

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(30)

    $timer.Add_Tick({
        try {
            $pinned = Get-QOEmailSyncStartDatePinned
            if ($pinned) { return }

            $today = (Get-Date).Date
            if ($Cal.SelectedDate -ne $today) {
                $Cal.SelectedDate = $today
                $Cal.DisplayDate  = $today
            }

            if ($Hint) { $Hint.Text = "Start date follows today until you select a date." }
        } catch { }
    })

    $timer.Start()
    $script:QOSettings_TodayTimer = $timer
}

function New-QOTSettingsView {
    Initialize-QOSettingsUIAssemblies

    $setMonitoredCmd = Get-Command Set-QOMonitoredAddresses -ErrorAction Stop
    $getMonitoredCmd = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction Stop

    $setPinnedCmd = Get-Command Set-QOEmailSyncStartDatePinned -ErrorAction Stop
    $getPinnedCmd = Get-Command Get-QOEmailSyncStartDatePinned -ErrorAction Stop

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

    $txtEmail = Get-QOControl -Root $root -Name "TxtEmail"        -Type ([System.Windows.Controls.TextBox])
    $btnAdd   = Get-QOControl -Root $root -Name "BtnAdd"          -Type ([System.Windows.Controls.Button])
    $btnRem   = Get-QOControl -Root $root -Name "BtnRemove"       -Type ([System.Windows.Controls.Button])
    $list     = Get-QOControl -Root $root -Name "LstEmails"       -Type ([System.Windows.Controls.ListBox])

    $cal      = Get-QOControl -Root $root -Name "CalEmailCutoff"  -Type ([System.Windows.Controls.Calendar])
    $btnToday = Get-QOControl -Root $root -Name "BtnFollowToday"  -Type ([System.Windows.Controls.Button])
    $hint     = Get-QOControl -Root $root -Name "LblHint"         -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }
    if (-not $cal)      { throw "CalEmailCutoff not found (Calendar)" }
    if (-not $btnToday) { throw "BtnFollowToday not found (Button)" }

    # Bind mailbox list
    $addresses = New-Object "System.Collections.ObjectModel.ObservableCollection[string]"
    foreach ($e in @(& $getMonitoredCmd)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }
    $list.ItemsSource = $addresses
    Write-QOSettingsUILog ("Bound mailbox list. Count=" + $addresses.Count)

    # Initialise calendar from pinned or today
    $pinned = $null
    try { $pinned = & $getPinnedCmd } catch { $pinned = $null }

    if ($pinned) {
        $cal.SelectedDate = $pinned.Date
        $cal.DisplayDate  = $pinned.Date
        if ($hint) { $hint.Text = "Pinned to " + $pinned.ToString("dd/MM/yyyy") + ". Click the clock button to follow today again." }
        Stop-QOSettingsTodayTimer
    } else {
        $today = (Get-Date).Date
        $cal.SelectedDate = $today
        $cal.DisplayDate  = $today
        if ($hint) { $hint.Text = "Start date follows today until you select a date." }
        Start-QOSettingsTodayTimer -Cal $cal -Hint $hint
    }

    # Unwire old handlers (if any)
    try { if ($script:QOSettings_AddClick) { $btnAdd.Remove_Click($script:QOSettings_AddClick) } } catch { }
    try { if ($script:QOSettings_RemClick) { $btnRem.Remove_Click($script:QOSettings_RemClick) } } catch { }
    try { if ($script:QOSettings_FollowTodayClick) { $btnToday.Remove_Click($script:QOSettings_FollowTodayClick) } } catch { }
    try { if ($script:QOSettings_CalendarChanged) { $cal.Remove_SelectedDatesChanged($script:QOSettings_CalendarChanged) } } catch { }

    # Add mailbox
    $script:QOSettings_AddClick = {
        try {
            $addr = ([string]$txtEmail.Text).Trim()
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

            if ($hint) { $hint.Text = "Added " + $addr }
        }
        catch {
            Write-QOSettingsUILog ("Add failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Add failed. Check logs." }
        }
    }.GetNewClosure()
    $btnAdd.Add_Click($script:QOSettings_AddClick)

    # Remove mailbox
    $script:QOSettings_RemClick = {
        try {
            $sel = $list.SelectedItem
            if (-not $sel) {
                if ($hint) { $hint.Text = "Select an address to remove." }
                return
            }

            [void]$addresses.Remove([string]$sel)

            $saveList = @($addresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $null = & $setMonitoredCmd -Addresses $saveList

            if ($hint) { $hint.Text = "Removed " + ([string]$sel) }
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Remove failed. Check logs." }
        }
    }.GetNewClosure()
    $btnRem.Add_Click($script:QOSettings_RemClick)

    # Follow today (clear pinned)
    $script:QOSettings_FollowTodayClick = {
        try {
            $null = & $setPinnedCmd -Date $null

            $today = (Get-Date).Date
            $cal.SelectedDate = $today
            $cal.DisplayDate  = $today

            if ($hint) { $hint.Text = "Start date follows today until you select a date." }
            Start-QOSettingsTodayTimer -Cal $cal -Hint $hint
        }
        catch {
            Write-QOSettingsUILog ("Follow today failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Follow today failed. Check logs." }
        }
    }.GetNewClosure()
    $btnToday.Add_Click($script:QOSettings_FollowTodayClick)

    # Calendar date selected (pin it)
    $script:QOSettings_CalendarChanged = {
        param($sender, $e)
        try {
            $d = $cal.SelectedDate
            if (-not $d) { return }

            $null = & $setPinnedCmd -Date ([datetime]$d)

            Stop-QOSettingsTodayTimer
            if ($hint) { $hint.Text = "Pinned to " + ([datetime]$d).ToString("dd/MM/yyyy") + ". Click the clock button to follow today again." }
        }
        catch {
            Write-QOSettingsUILog ("Calendar change failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Date select failed. Check logs." }
        }
    }.GetNewClosure()
    $cal.Add_SelectedDatesChanged($script:QOSettings_CalendarChanged)

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
