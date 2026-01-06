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
$script:QOSettings_AddHandler = $null
$script:QOSettings_RemHandler = $null
$script:QOSettings_UseTodayHandler = $null
$script:QOSettings_CalHandler = $null
$script:QOSettings_Timer = $null

# Guard to prevent auto "follow today" updates from pinning
$script:QOSettings_AutoUpdating = $false

function New-QOTSettingsView {
    Initialize-QOSettingsUIAssemblies

    # Capture commands NOW, so handlers can always call them later
    $setMonitoredCmd    = Get-Command Set-QOMonitoredAddresses -ErrorAction Stop
    $getSettingsCmd     = Get-Command Get-QOSettings -ErrorAction Stop
    $getMonitoredCmd    = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction Stop
    $getPinnedCmd       = Get-Command Get-QOEmailSyncStartDatePinned -ErrorAction Stop
    $setPinnedCmd       = Get-Command Set-QOEmailSyncStartDatePinned -ErrorAction Stop
    $getEffectiveCmd    = Get-Command Get-QOEmailSyncStartDateEffective -ErrorAction Stop

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

    $txtEmail  = Get-QOControl -Root $root -Name "TxtEmail"      -Type ([System.Windows.Controls.TextBox])
    $btnAdd    = Get-QOControl -Root $root -Name "BtnAdd"        -Type ([System.Windows.Controls.Button])
    $btnRem    = Get-QOControl -Root $root -Name "BtnRemove"     -Type ([System.Windows.Controls.Button])
    $list      = Get-QOControl -Root $root -Name "LstEmails"     -Type ([System.Windows.Controls.ListBox])
    $btnToday  = Get-QOControl -Root $root -Name "BtnUseToday"   -Type ([System.Windows.Controls.Button])
    $cal       = Get-QOControl -Root $root -Name "CalEmailCutoff"-Type ([System.Windows.Controls.Calendar])
    $hint      = Get-QOControl -Root $root -Name "LblHint"       -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }
    if (-not $btnToday) { throw "BtnUseToday not found (Button)" }
    if (-not $cal)      { throw "CalEmailCutoff not found (Calendar)" }

    # -------------------------
    # Mailbox list binding
    # -------------------------
    $addresses = New-Object "System.Collections.ObjectModel.ObservableCollection[string]"
    foreach ($e in @(& $getMonitoredCmd)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }
    $list.ItemsSource = $addresses
    Write-QOSettingsUILog ("Bound mailbox list. Count=" + $addresses.Count)

    # Remove previous handlers
    try { if ($script:QOSettings_AddHandler)     { $btnAdd.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler) } } catch { }
    try { if ($script:QOSettings_RemHandler)     { $btnRem.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler) } } catch { }
    try { if ($script:QOSettings_UseTodayHandler){ $btnToday.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_UseTodayHandler) } } catch { }
    try {
        if ($script:QOSettings_CalHandler) {
            # IMPORTANT: calendar uses SelectionChangedEventHandler delegate
            $cal.RemoveHandler([System.Windows.Controls.Calendar]::SelectedDatesChangedEvent, $script:QOSettings_CalHandler)
        }
    } catch { }

    # Stop old timer if any
    try {
        if ($script:QOSettings_Timer) {
            $script:QOSettings_Timer.Stop()
            $script:QOSettings_Timer = $null
        }
    } catch { }

    function Set-HintSafe {
        param([string]$Text)
        try { if ($hint) { $hint.Text = $Text } } catch { }
    }

    function Apply-FollowTodayState {
        # Only call this when "not pinned"
        try {
            $script:QOSettings_AutoUpdating = $true
            $today = (Get-Date).Date
            $cal.DisplayDate = $today
            $cal.SelectedDate = $today
        } catch { }
        finally {
            $script:QOSettings_AutoUpdating = $false
        }

        Set-HintSafe "Start date follows today until you select a date."
    }

    function Apply-PinnedState {
        param([datetime]$PinnedDate)

        try {
            $script:QOSettings_AutoUpdating = $true
            $cal.DisplayDate = $PinnedDate.Date
            $cal.SelectedDate = $PinnedDate.Date
        } catch { }
        finally {
            $script:QOSettings_AutoUpdating = $false
        }

        Set-HintSafe ("Pinned start date: " + $PinnedDate.ToString("dd/MM/yyyy"))
    }

    # -------------------------
    # Initialise calendar state
    # -------------------------
    $pinnedRaw = ""
    try { $pinnedRaw = [string](& $getPinnedCmd) } catch { $pinnedRaw = "" }

    if ([string]::IsNullOrWhiteSpace($pinnedRaw)) {
        Apply-FollowTodayState
    } else {
        try {
            $pinnedDate = [datetime]::ParseExact($pinnedRaw, "yyyy-MM-dd", $null)
            Apply-PinnedState -PinnedDate $pinnedDate
        } catch {
            # If parsing fails, fall back to follow today
            try { $null = & $setPinnedCmd -Date $null } catch { }
            Apply-FollowTodayState
        }
    }

    # Timer to keep calendar aligned with today while not pinned
    $script:QOSettings_Timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:QOSettings_Timer.Interval = [TimeSpan]::FromSeconds(30)
    $script:QOSettings_Timer.Add_Tick({
        try {
            $p = ""
            try { $p = [string](& $getPinnedCmd) } catch { $p = "" }

            if ([string]::IsNullOrWhiteSpace($p)) {
                Apply-FollowTodayState
            }
        } catch { }
    })
    $script:QOSettings_Timer.Start()

    # -------------------------
    # Handlers
    # -------------------------
    $script:QOSettings_AddHandler = [System.Windows.RoutedEventHandler]{
        try {
            $addr = ([string]$txtEmail.Text).Trim()
            Write-QOSettingsUILog ("Add clicked. Input='" + $addr + "'")

            if (-not $addr) {
                Set-HintSafe "Enter an email address."
                return
            }

            $lower = $addr.ToLower()
            foreach ($x in $addresses) {
                if (([string]$x).Trim().ToLower() -eq $lower) {
                    $txtEmail.Text = ""
                    Set-HintSafe "Already exists."
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

            Set-HintSafe "Added $addr"
        }
        catch {
            Write-QOSettingsUILog ("Add failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Add stack: " + $_.ScriptStackTrace)
            Set-HintSafe "Add failed. Check logs."
        }
    }.GetNewClosure()

    $script:QOSettings_RemHandler = [System.Windows.RoutedEventHandler]{
        try {
            $sel = $list.SelectedItem
            Write-QOSettingsUILog ("Remove clicked. Selected='" + ($sel + "") + "'")

            if (-not $sel) {
                Set-HintSafe "Select an address to remove."
                return
            }

            [void]$addresses.Remove([string]$sel)

            $saveList = @($addresses | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $null = & $setMonitoredCmd -Addresses $saveList

            $after = & $getSettingsCmd
            $count = @($after.Tickets.EmailIntegration.MonitoredAddresses).Count
            Write-QOSettingsUILog ("Removed. Stored count=" + $count)

            Set-HintSafe "Removed $sel"
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Remove stack: " + $_.ScriptStackTrace)
            Set-HintSafe "Remove failed. Check logs."
        }
    }.GetNewClosure()

    # Follow today (clears pinned value)
    $script:QOSettings_UseTodayHandler = [System.Windows.RoutedEventHandler]{
        try {
            $null = & $setPinnedCmd -Date $null
            Apply-FollowTodayState
            Write-QOSettingsUILog "Follow today clicked. Pinned cleared."
        }
        catch {
            Write-QOSettingsUILog ("Follow today failed: " + $_.Exception.ToString())
            Set-HintSafe "Follow today failed. Check logs."
        }
    }.GetNewClosure()

    # Calendar selection pins the date
    $script:QOSettings_CalHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        try {
            if ($script:QOSettings_AutoUpdating) { return }

            $d = $cal.SelectedDate
            if ($null -eq $d) { return }

            $null = & $setPinnedCmd -Date ([datetime]$d)
            Apply-PinnedState -PinnedDate ([datetime]$d)
            Write-QOSettingsUILog ("Pinned date selected: " + ([datetime]$d).ToString("yyyy-MM-dd"))
        }
        catch {
            Write-QOSettingsUILog ("Calendar select failed: " + $_.Exception.ToString())
            Set-HintSafe "Date selection failed. Check logs."
        }
    }.GetNewClosure()

    # Wire handlers using AddHandler (matches delegate types correctly)
    $btnAdd.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
    $btnRem.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)
    $btnToday.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_UseTodayHandler)

    # Calendar SelectedDatesChanged uses SelectionChangedEventHandler delegate (THIS was your mismatch earlier)
    $cal.AddHandler([System.Windows.Controls.Calendar]::SelectedDatesChangedEvent, $script:QOSettings_CalHandler)

    Write-QOSettingsUILog "Wired handlers using AddHandler"

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
