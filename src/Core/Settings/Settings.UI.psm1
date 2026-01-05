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
$script:QOSettings_CalChangedHandler = $null
$script:QOSettings_TodayHandler = $null
$script:QOSettings_FollowTodayHandler = $null

function New-QOTSettingsView {
    Initialize-QOSettingsUIAssemblies

    # Commands
    $setMonitoredCmd = Get-Command Set-QOMonitoredAddresses -ErrorAction Stop
    $getSettingsCmd  = Get-Command Get-QOSettings -ErrorAction Stop
    $getMonitoredCmd = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction Stop

    $getCutoffCmd = Get-Command Get-QOEmailSyncStartDate -ErrorAction Stop
    $setCutoffCmd = Get-Command Set-QOEmailSyncStartDate -ErrorAction Stop

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
    $txtEmail = Get-QOControl -Root $root -Name "TxtEmail"  -Type ([System.Windows.Controls.TextBox])
    $btnAdd   = Get-QOControl -Root $root -Name "BtnAdd"    -Type ([System.Windows.Controls.Button])
    $btnRem   = Get-QOControl -Root $root -Name "BtnRemove" -Type ([System.Windows.Controls.Button])
    $list     = Get-QOControl -Root $root -Name "LstEmails" -Type ([System.Windows.Controls.ListBox])
    $hint     = Get-QOControl -Root $root -Name "LblHint"   -Type ([System.Windows.Controls.TextBlock])

    $cal      = Get-QOControl -Root $root -Name "CalEmailCutoff"        -Type ([System.Windows.Controls.Calendar])
    $lblValue = Get-QOControl -Root $root -Name "LblCutoffValue"        -Type ([System.Windows.Controls.TextBlock])
    $btnToday = Get-QOControl -Root $root -Name "BtnCutoffToday"        -Type ([System.Windows.Controls.Button])
    $btnFollow= Get-QOControl -Root $root -Name "BtnCutoffFollowToday"  -Type ([System.Windows.Controls.Button])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }
    if (-not $cal)      { throw "CalEmailCutoff not found (Calendar)" }
    if (-not $lblValue) { throw "LblCutoffValue not found (TextBlock)" }
    if (-not $btnToday) { throw "BtnCutoffToday not found (Button)" }
    if (-not $btnFollow){ throw "BtnCutoffFollowToday not found (Button)" }

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

    # -------------------------
    # Calendar initial load
    # -------------------------
    $script:QOSettings_InternalCalUpdate = $false

    function Set-CutoffLabel {
        param([string]$Stored, [datetime]$Selected)

        if ([string]::IsNullOrWhiteSpace($Stored)) {
            $lblValue.Text = "(following today: " + $Selected.ToString("dd/MM/yyyy") + ")"
        } else {
            $lblValue.Text = $Selected.ToString("dd/MM/yyyy")
        }
    }

    $stored = ""
    try { $stored = [string](& $getCutoffCmd) } catch { $stored = "" }
    $stored = ($stored + "").Trim()

    $initialDate = (Get-Date).Date
    if (-not [string]::IsNullOrWhiteSpace($stored)) {
        try {
            $parsed = [datetime]::ParseExact($stored, "yyyy-MM-dd", $null)
            $initialDate = $parsed.Date
        } catch {
            Write-QOSettingsUILog ("Stored cutoff date invalid: '" + $stored + "'")
            $stored = ""
            $initialDate = (Get-Date).Date
        }
    }

    $script:QOSettings_InternalCalUpdate = $true
    $cal.SelectedDate = $initialDate
    $cal.DisplayDate  = $initialDate
    $script:QOSettings_InternalCalUpdate = $false

    Set-CutoffLabel -Stored $stored -Selected $initialDate

    # -------------------------
    # Remove old handlers
    # -------------------------
    try { if ($script:QOSettings_AddHandler) { $btnAdd.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler) } } catch { }
    try { if ($script:QOSettings_RemHandler) { $btnRem.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler) } } catch { }

    try { if ($script:QOSettings_CalChangedHandler) { $cal.RemoveHandler([System.Windows.Controls.Calendar]::SelectedDatesChangedEvent, $script:QOSettings_CalChangedHandler) } } catch { }
    try { if ($script:QOSettings_TodayHandler) { $btnToday.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_TodayHandler) } } catch { }
    try { if ($script:QOSettings_FollowTodayHandler) { $btnFollow.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_FollowTodayHandler) } } catch { }

    # -------------------------
    # Add address
    # -------------------------
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
            if ($hint) { $hint.Text = "Add failed. Check logs." }
        }
    }.GetNewClosure()

    # -------------------------
    # Remove address
    # -------------------------
    $script:QOSettings_RemHandler = [System.Windows.RoutedEventHandler]{
        try {
            $sel = $list.SelectedItem

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
            if ($hint) { $hint.Text = "Remove failed. Check logs." }
        }
    }.GetNewClosure()

    # -------------------------
    # Calendar selection change (this is the moment we SAVE)
    # -------------------------
    $script:QOSettings_CalChangedHandler = [System.Windows.Controls.SelectionChangedEventHandler]{
        try {
            if ($script:QOSettings_InternalCalUpdate) { return }

            $d = $cal.SelectedDate
            if (-not $d) { return }

            $dt = ([datetime]$d).Date
            $storeStr = $dt.ToString("yyyy-MM-dd")

            $null = & $setCutoffCmd -DateString $storeStr

            Set-CutoffLabel -Stored $storeStr -Selected $dt
            if ($hint) { $hint.Text = "Saved start date: " + $dt.ToString("dd/MM/yyyy") }
        }
        catch {
            Write-QOSettingsUILog ("Calendar save failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Calendar save failed. Check logs." }
        }
    }.GetNewClosure()

    # Jump to today (does not clear saved date, just navigates)
    $script:QOSettings_TodayHandler = [System.Windows.RoutedEventHandler]{
        try {
            $today = (Get-Date).Date
            $script:QOSettings_InternalCalUpdate = $true
            $cal.DisplayDate = $today
            $cal.SelectedDate = $today
            $script:QOSettings_InternalCalUpdate = $false
        } catch {
            Write-QOSettingsUILog ("Today button failed: " + $_.Exception.ToString())
        }
    }.GetNewClosure()

    # Follow today (clears saved date)
    $script:QOSettings_FollowTodayHandler = [System.Windows.RoutedEventHandler]{
        try {
            $null = & $setCutoffCmd -DateString ""

            $today = (Get-Date).Date
            $script:QOSettings_InternalCalUpdate = $true
            $cal.DisplayDate = $today
            $cal.SelectedDate = $today
            $script:QOSettings_InternalCalUpdate = $false

            Set-CutoffLabel -Stored "" -Selected $today
            if ($hint) { $hint.Text = "Following today's date again." }
        } catch {
            Write-QOSettingsUILog ("Follow today failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Follow today failed. Check logs." }
        }
    }.GetNewClosure()

    # Wire handlers
    $btnAdd.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
    $btnRem.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)

    $cal.AddHandler([System.Windows.Controls.Calendar]::SelectedDatesChangedEvent, $script:QOSettings_CalChangedHandler)
    $btnToday.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_TodayHandler)
    $btnFollow.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_FollowTodayHandler)

    Write-QOSettingsUILog "Settings view loaded and handlers wired."

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
