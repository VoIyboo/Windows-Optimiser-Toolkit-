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
# Calendar flyout (custom Window)
# ------------------------------------------------------------
function Show-QOTCalendarFlyout {
    param(
        [Parameter(Mandatory)][System.Windows.FrameworkElement]$Anchor,
        [Parameter(Mandatory)][datetime]$InitialDate
    )

    Initialize-QOSettingsUIAssemblies

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="320"
        Height="360"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        ShowInTaskbar="False"
        Topmost="True">
    <Border Background="#0B1220"
            BorderBrush="#1F2937"
            BorderThickness="1"
            CornerRadius="14"
            Padding="12">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <DockPanel Grid.Row="0" Margin="0,0,0,10">
                <TextBlock x:Name="LblTitle"
                           DockPanel.Dock="Left"
                           Foreground="#E5E7EB"
                           FontSize="14"
                           FontWeight="SemiBold"
                           VerticalAlignment="Center"
                           Text="Select date"/>
                <Button x:Name="BtnClose"
                        DockPanel.Dock="Right"
                        Width="30"
                        Height="30"
                        Background="#0F172A"
                        BorderBrush="#1F2937"
                        BorderThickness="1"
                        Cursor="Hand">
                    <TextBlock FontFamily="Segoe MDL2 Assets"
                               Foreground="#E5E7EB"
                               HorizontalAlignment="Center"
                               VerticalAlignment="Center"
                               Text="&#xE711;"/>
                </Button>
            </DockPanel>

            <Calendar x:Name="Cal"
                      Grid.Row="1"
                      Background="#0B1220"
                      Foreground="#E5E7EB"
                      BorderThickness="0"
                      SelectionMode="SingleDate"
                      IsTodayHighlighted="True" />

            <DockPanel Grid.Row="2" Margin="0,10,0,0">
                <Button x:Name="BtnClear"
                        DockPanel.Dock="Left"
                        Padding="10,6"
                        Background="#0F172A"
                        BorderBrush="#1F2937"
                        BorderThickness="1"
                        Foreground="#E5E7EB"
                        Cursor="Hand">
                    Clear
                </Button>

                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="BtnCancel"
                            Margin="0,0,8,0"
                            Padding="10,6"
                            Background="#0F172A"
                            BorderBrush="#1F2937"
                            BorderThickness="1"
                            Foreground="#E5E7EB"
                            Cursor="Hand">
                        Cancel
                    </Button>

                    <Button x:Name="BtnOk"
                            Padding="10,6"
                            Background="#2563EB"
                            BorderBrush="#2563EB"
                            BorderThickness="1"
                            Foreground="White"
                            Cursor="Hand">
                        OK
                    </Button>
                </StackPanel>
            </DockPanel>
        </Grid>
    </Border>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)

    $cal      = $win.FindName("Cal")
    $btnOk    = $win.FindName("BtnOk")
    $btnCancel= $win.FindName("BtnCancel")
    $btnClose = $win.FindName("BtnClose")
    $btnClear = $win.FindName("BtnClear")

    $cal.DisplayDate = $InitialDate
    $cal.SelectedDate = $InitialDate

    # Position under the anchor
    $pt = $Anchor.PointToScreen([System.Windows.Point]::new(0, $Anchor.ActualHeight))
    $win.Left = $pt.X
    $win.Top  = $pt.Y + 6

    $selected = $null
    $cleared  = $false

    $btnClose.Add_Click({
        $win.DialogResult = $false
        $win.Close()
    })

    $btnCancel.Add_Click({
        $win.DialogResult = $false
        $win.Close()
    })

    $btnClear.Add_Click({
        $cleared = $true
        $win.DialogResult = $true
        $win.Close()
    })

    $btnOk.Add_Click({
        $selected = $cal.SelectedDate
        $win.DialogResult = $true
        $win.Close()
    })

    $null = $win.ShowDialog()

    if ($cleared) {
        return [pscustomobject]@{ Cleared = $true; Date = $null }
    }

    if ($selected) {
        return [pscustomobject]@{ Cleared = $false; Date = [datetime]$selected }
    }

    return $null
}

# ------------------------------------------------------------
# Stored handlers to avoid double wiring
# ------------------------------------------------------------
$script:QOSettings_AddHandler    = $null
$script:QOSettings_RemHandler    = $null
$script:QOSettings_PickDateHandler = $null

function New-QOTSettingsView {
    Initialize-QOSettingsUIAssemblies

    # Capture commands NOW
    $setMonitoredCmd = Get-Command Set-QOMonitoredAddresses -ErrorAction Stop
    $getSettingsCmd  = Get-Command Get-QOSettings -ErrorAction Stop
    $getMonitoredCmd = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction Stop

    $getCutoffStateCmd = Get-Command Get-QOEmailSyncStartDateState -ErrorAction Stop
    $setCutoffPinnedCmd = Get-Command Set-QOEmailSyncStartDatePinned -ErrorAction Stop
    $clearCutoffCmd = Get-Command Clear-QOEmailSyncStartDate -ErrorAction Stop

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

    $txtEmail   = Get-QOControl -Root $root -Name "TxtEmail"  -Type ([System.Windows.Controls.TextBox])
    $btnAdd     = Get-QOControl -Root $root -Name "BtnAdd"    -Type ([System.Windows.Controls.Button])
    $btnRem     = Get-QOControl -Root $root -Name "BtnRemove" -Type ([System.Windows.Controls.Button])
    $list       = Get-QOControl -Root $root -Name "LstEmails" -Type ([System.Windows.Controls.ListBox])
    $hint       = Get-QOControl -Root $root -Name "LblHint"   -Type ([System.Windows.Controls.TextBlock])

    $txtCutoff  = Get-QOControl -Root $root -Name "TxtEmailCutoff" -Type ([System.Windows.Controls.TextBox])
    $btnPick    = Get-QOControl -Root $root -Name "BtnPickEmailCutoff" -Type ([System.Windows.Controls.Button])
    $cutHint    = Get-QOControl -Root $root -Name "LblEmailCutoffHint" -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }
    if (-not $txtCutoff){ throw "TxtEmailCutoff not found (TextBox)" }
    if (-not $btnPick)  { throw "BtnPickEmailCutoff not found (Button)" }

    # Load addresses from settings
    $addresses = New-Object "System.Collections.ObjectModel.ObservableCollection[string]"
    foreach ($e in @(& $getMonitoredCmd)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }
    $list.ItemsSource = $addresses

    # Load cutoff display
    $state = & $getCutoffStateCmd
    $displayDate = Get-Date
    $pinned = $false

    try { $pinned = [bool]$state.Pinned } catch { $pinned = $false }
    if ($pinned -and $state.Date) {
        $displayDate = [datetime]$state.Date
        if ($cutHint) { $cutHint.Text = "Pinned. Only emails from this date onwards will be considered during the initial import." }
    } else {
        if ($cutHint) { $cutHint.Text = "Email sync start date will follow today's date until you choose one." }
    }

    # AU style display
    $txtCutoff.Text = $displayDate.ToString("dd/MM/yyyy")

    # Remove old handlers (emails)
    try { if ($script:QOSettings_AddHandler) { $btnAdd.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler) } } catch { }
    try { if ($script:QOSettings_RemHandler) { $btnRem.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler) } } catch { }

    # Remove old handler (date)
    try { if ($script:QOSettings_PickDateHandler) { $btnPick.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_PickDateHandler) } } catch { }

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

            if ($hint) { $hint.Text = "Removed $sel" }
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Remove stack: " + $_.ScriptStackTrace)
        }
    }.GetNewClosure()

    $script:QOSettings_PickDateHandler = [System.Windows.RoutedEventHandler]{
        try {
            # Determine initial date for picker
            $state = & $getCutoffStateCmd
            $init = Get-Date
            $isPinned = $false
            try { $isPinned = [bool]$state.Pinned } catch { $isPinned = $false }
            if ($isPinned -and $state.Date) {
                $init = [datetime]$state.Date
            }

            $pick = Show-QOTCalendarFlyout -Anchor $btnPick -InitialDate $init
            if (-not $pick) { return }

            if ($pick.Cleared) {
                $null = & $clearCutoffCmd

                $today = Get-Date
                $txtCutoff.Text = $today.ToString("dd/MM/yyyy")
                if ($cutHint) { $cutHint.Text = "Email sync start date will follow today's date until you choose one." }
                if ($hint) { $hint.Text = "Cleared pinned date. Following today's date." }
                return
            }

            if ($pick.Date) {
                $chosen = [datetime]$pick.Date
                $null = & $setCutoffPinnedCmd -Date $chosen

                $txtCutoff.Text = $chosen.ToString("dd/MM/yyyy")
                if ($cutHint) { $cutHint.Text = "Pinned. Only emails from this date onwards will be considered during the initial import." }
                if ($hint) { $hint.Text = "Pinned start date: " + $chosen.ToString("dd/MM/yyyy") }
            }
        }
        catch {
            Write-QOSettingsUILog ("Pick date failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Pick date stack: " + $_.ScriptStackTrace)
            if ($hint) { $hint.Text = "Date picker failed. Check logs." }
        }
    }.GetNewClosure()

    $btnAdd.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
    $btnRem.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)
    $btnPick.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_PickDateHandler)

    Write-QOSettingsUILog "Wired handlers using AddHandler"

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
