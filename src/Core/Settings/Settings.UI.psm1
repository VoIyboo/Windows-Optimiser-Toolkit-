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
$script:QOSettings_AddHandler   = $null
$script:QOSettings_RemHandler   = $null
$script:QOSettings_TodayHandler = $null

# Event subscription tokens for Register-ObjectEvent (so we can cleanly unregister)
$script:QOSettings_CalSub   = $null

function New-QOTSettingsView {
    Initialize-QOSettingsUIAssemblies

    $setMonitoredCmd = Get-Command Set-QOMonitoredAddresses -ErrorAction Stop
    $getMonitoredCmd = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction Stop

    $getCutoffStateCmd      = Get-Command Get-QOEmailSyncStartDateState -ErrorAction Stop
    $setCutoffPinnedCmd     = Get-Command Set-QOEmailSyncStartDatePinned -ErrorAction Stop
    $clearCutoffPinnedCmd   = Get-Command Clear-QOEmailSyncStartDatePinned -ErrorAction Stop

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

    $txtEmail   = Get-QOControl -Root $root -Name "TxtEmail"        -Type ([System.Windows.Controls.TextBox])
    $btnAdd     = Get-QOControl -Root $root -Name "BtnAdd"          -Type ([System.Windows.Controls.Button])
    $btnRem     = Get-QOControl -Root $root -Name "BtnRemove"       -Type ([System.Windows.Controls.Button])
    $list       = Get-QOControl -Root $root -Name "LstEmails"       -Type ([System.Windows.Controls.ListBox])
    $hint       = Get-QOControl -Root $root -Name "LblHint"         -Type ([System.Windows.Controls.TextBlock])

    $txtCutoff  = Get-QOControl -Root $root -Name "TxtEmailCutoff"  -Type ([System.Windows.Controls.TextBox])
    $calCutoff  = Get-QOControl -Root $root -Name "CalEmailCutoff"  -Type ([System.Windows.Controls.Calendar])
    $btnToday   = Get-QOControl -Root $root -Name "BtnUseToday"     -Type ([System.Windows.Controls.Button])

    if (-not $txtEmail)  { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)    { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)    { throw "BtnRemove not found (Button)" }
    if (-not $list)      { throw "LstEmails not found (ListBox)" }

    if (-not $txtCutoff) { throw "TxtEmailCutoff not found (TextBox)" }
    if (-not $calCutoff) { throw "CalEmailCutoff not found (Calendar)" }
    if (-not $btnToday)  { throw "BtnUseToday not found (Button)" }

    # Load mailbox list
    $addresses = New-Object "System.Collections.ObjectModel.ObservableCollection[string]"
    foreach ($e in @(& $getMonitoredCmd)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }
    $list.ItemsSource = $addresses
    Write-QOSettingsUILog ("Bound mailbox list. Count=" + $addresses.Count)

    # Init cutoff UI
    $state = & $getCutoffStateCmd
    $today = (Get-Date).Date

    $pinned = $false
    $pinnedDate = $null

    try { $pinned = [bool]$state.Pinned } catch { $pinned = $false }

    if ($pinned) {
        try {
            $pinnedDate = [datetime]::ParseExact([string]$state.DateStr, "yyyy-MM-dd", $null)
        } catch {
            $pinned = $false
        }
    }

    if ($pinned -and $pinnedDate) {
        $txtCutoff.Text = $pinnedDate.ToString("dd/MM/yyyy")
        $calCutoff.SelectedDate = $pinnedDate
        $calCutoff.DisplayDate  = $pinnedDate
        if ($hint) { $hint.Text = "Pinned start date is saved. Select a different date to update it, or click the clock to follow today." }
    } else {
        $txtCutoff.Text = $today.ToString("dd/MM/yyyy")
        $calCutoff.SelectedDate = $today
        $calCutoff.DisplayDate  = $today
        if ($hint) { $hint.Text = "Start date follows today until you select a date." }
    }

    # Unwire previous click handlers
    try { if ($script:QOSettings_AddHandler) { $btnAdd.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler) } } catch { }
    try { if ($script:QOSettings_RemHandler) { $btnRem.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler) } } catch { }
    try { if ($script:QOSettings_TodayHandler) { $btnToday.Remove_Click($script:QOSettings_TodayHandler) } } catch { }

    # Unregister old calendar event subscription
    try {
        if ($script:QOSettings_CalSub) {
            Unregister-Event -SubscriptionId $script:QOSettings_CalSub.Id -ErrorAction SilentlyContinue
            $script:QOSettings_CalSub = $null
        }
    } catch { }

    # Add mailbox handler
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

            if ($hint) { $hint.Text = "Added $addr" }
        }
        catch {
            Write-QOSettingsUILog ("Add failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Add stack: " + $_.ScriptStackTrace)
            if ($hint) { $hint.Text = "Add failed. Check logs." }
        }
    }.GetNewClosure()

    # Remove mailbox handler
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

            if ($hint) { $hint.Text = "Removed $sel" }
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Remove stack: " + $_.ScriptStackTrace)
            if ($hint) { $hint.Text = "Remove failed. Check logs." }
        }
    }.GetNewClosure()

    # Use today handler
    $script:QOSettings_TodayHandler = {
        try {
            $t = (Get-Date).Date
            $txtCutoff.Text = $t.ToString("dd/MM/yyyy")
            $calCutoff.SelectedDate = $t
            $calCutoff.DisplayDate  = $t

            $null = & $clearCutoffPinnedCmd

            if ($hint) { $hint.Text = "Start date now follows today until you select a date." }
            Write-QOSettingsUILog "Cutoff set to follow today (unpinned)"
        }
        catch {
            Write-QOSettingsUILog ("Use today failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Use today stack: " + $_.ScriptStackTrace)
            if ($hint) { $hint.Text = "Use today failed. Check logs." }
        }
    }.GetNewClosure()

    # Register calendar selection using Register-ObjectEvent (no delegate mismatch)
    $script:QOSettings_CalSub = Register-ObjectEvent -InputObject $calCutoff -EventName SelectedDatesChanged -Action {
        try {
            $d = $Event.Sender.SelectedDate
            if (-not $d) { return }

            $dt = [datetime]$d
            $txtCutoff.Text = $dt.ToString("dd/MM/yyyy")

            $null = & $setCutoffPinnedCmd -Date $dt

            if ($hint) { $hint.Text = "Pinned start date saved: " + $dt.ToString("dd/MM/yyyy") }
            Write-QOSettingsUILog ("Pinned cutoff saved: " + $dt.ToString("yyyy-MM-dd"))
        }
        catch {
            Write-QOSettingsUILog ("Calendar select failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Calendar stack: " + $_.ScriptStackTrace)
            if ($hint) { $hint.Text = "Date save failed. Check logs." }
        }
    }

    $btnAdd.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
    $btnRem.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)
    $btnToday.Add_Click($script:QOSettings_TodayHandler)

    Write-QOSettingsUILog "Wired handlers: mail add/remove, calendar event subscription, use today"

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
