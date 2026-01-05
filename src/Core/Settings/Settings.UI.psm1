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
$script:QOSettings_PickDateHandler = $null

function Show-QODatePickerFlyout {
    param(
        [Parameter(Mandatory)]
        [datetime]$InitialDate
    )

    Initialize-QOSettingsUIAssemblies

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        SizeToContent="WidthAndHeight"
        Topmost="True">

    <Border Background="#0B1220"
            BorderBrush="#1F2937"
            BorderThickness="1"
            CornerRadius="14"
            Padding="12">

        <StackPanel Width="320">

            <DockPanel Margin="0,0,0,10" LastChildFill="True">
                <TextBlock x:Name="LblHeader"
                           DockPanel.Dock="Left"
                           Foreground="#E5E7EB"
                           FontSize="14"
                           FontWeight="SemiBold"
                           VerticalAlignment="Center" />

                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="BtnPrev"
                            Width="34" Height="34"
                            Background="#0F172A"
                            BorderBrush="#1F2937"
                            BorderThickness="1"
                            Margin="0,0,8,0"
                            Cursor="Hand">
                        <TextBlock Text="&#xE72B;"
                                   FontFamily="Segoe MDL2 Assets"
                                   Foreground="#E5E7EB"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Button>

                    <Button x:Name="BtnNext"
                            Width="34" Height="34"
                            Background="#0F172A"
                            BorderBrush="#1F2937"
                            BorderThickness="1"
                            Cursor="Hand">
                        <TextBlock Text="&#xE72A;"
                                   FontFamily="Segoe MDL2 Assets"
                                   Foreground="#E5E7EB"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Button>
                </StackPanel>
            </DockPanel>

            <Calendar x:Name="Cal"
                      Background="Transparent"
                      BorderThickness="0"
                      Foreground="#E5E7EB"
                      SelectionMode="SingleDate"
                      IsTodayHighlighted="True" />

            <DockPanel Margin="0,10,0,0" LastChildFill="False">
                <Button x:Name="BtnCancel"
                        DockPanel.Dock="Right"
                        Height="34"
                        MinWidth="90"
                        Background="#0F172A"
                        BorderBrush="#1F2937"
                        BorderThickness="1"
                        Foreground="#E5E7EB"
                        Cursor="Hand"
                        Margin="8,0,0,0"
                        Content="Cancel"/>

                <Button x:Name="BtnOK"
                        DockPanel.Dock="Right"
                        Height="34"
                        MinWidth="90"
                        Background="#2563EB"
                        BorderBrush="#2563EB"
                        BorderThickness="1"
                        Foreground="White"
                        Cursor="Hand"
                        Content="OK"/>
            </DockPanel>

        </StackPanel>

    </Border>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)

    $cal = $win.FindName("Cal")
    $lbl = $win.FindName("LblHeader")
    $btnPrev = $win.FindName("BtnPrev")
    $btnNext = $win.FindName("BtnNext")
    $btnOK = $win.FindName("BtnOK")
    $btnCancel = $win.FindName("BtnCancel")

    $script:selectedDate = $null

    $cal.DisplayDate = $InitialDate.Date
    $cal.SelectedDate = $InitialDate.Date

    $updateHeader = {
        try { $lbl.Text = $cal.DisplayDate.ToString("MMMM yyyy") } catch { }
    }.GetNewClosure()

    & $updateHeader

    $btnPrev.Add_Click({
        try {
            $cal.DisplayDate = $cal.DisplayDate.AddMonths(-1)
            & $updateHeader
        } catch { }
    }.GetNewClosure())

    $btnNext.Add_Click({
        try {
            $cal.DisplayDate = $cal.DisplayDate.AddMonths(1)
            & $updateHeader
        } catch { }
    }.GetNewClosure())

    $cal.Add_SelectedDatesChanged({
        try {
            if ($cal.SelectedDate) {
                $script:selectedDate = [datetime]$cal.SelectedDate
            }
        } catch { }
    }.GetNewClosure())

    $btnOK.Add_Click({
        try {
            if (-not $script:selectedDate -and $cal.SelectedDate) {
                $script:selectedDate = [datetime]$cal.SelectedDate
            }
        } catch { }
        $win.DialogResult = $true
        $win.Close()
    }.GetNewClosure())

    $btnCancel.Add_Click({
        $win.DialogResult = $false
        $win.Close()
    }.GetNewClosure())

    $null = $win.ShowDialog()
    return $script:selectedDate
}

function New-QOTSettingsView {
    Initialize-QOSettingsUIAssemblies

    # Commands
    $setMonitoredCmd = Get-Command Set-QOMonitoredAddresses -ErrorAction Stop
    $getSettingsCmd  = Get-Command Get-QOSettings -ErrorAction Stop
    $getDateCmd      = Get-Command Get-QOEmailSyncStartDate -ErrorAction Stop
    $setDateCmd      = Get-Command Set-QOEmailSyncStartDate -ErrorAction Stop

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

    $txtEmail = Get-QOControl -Root $root -Name "TxtEmail"  -Type ([System.Windows.Controls.TextBox])
    $btnAdd   = Get-QOControl -Root $root -Name "BtnAdd"    -Type ([System.Windows.Controls.Button])
    $btnRem   = Get-QOControl -Root $root -Name "BtnRemove" -Type ([System.Windows.Controls.Button])
    $list     = Get-QOControl -Root $root -Name "LstEmails" -Type ([System.Windows.Controls.ListBox])
    $hint     = Get-QOControl -Root $root -Name "LblHint"   -Type ([System.Windows.Controls.TextBlock])

    $txtCutoff = Get-QOControl -Root $root -Name "TxtEmailCutoff" -Type ([System.Windows.Controls.TextBox])
    $btnPick   = Get-QOControl -Root $root -Name "BtnPickEmailCutoff" -Type ([System.Windows.Controls.Button])
    $lblCutoffHint = Get-QOControl -Root $root -Name "LblEmailCutoffHint" -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }

    if (-not $txtCutoff) { throw "TxtEmailCutoff not found (TextBox). Make sure SettingsWindow.xaml includes it." }
    if (-not $btnPick)   { throw "BtnPickEmailCutoff not found (Button). Make sure SettingsWindow.xaml includes it." }
    if (-not $lblCutoffHint) { throw "LblEmailCutoffHint not found (TextBlock)." }

    # Load monitored addresses
    $addresses = New-Object "System.Collections.ObjectModel.ObservableCollection[string]"
    $getMonitoredCmd = Get-Command Get-QOMonitoredMailboxAddresses -ErrorAction Stop

    foreach ($e in @(& $getMonitoredCmd)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }

    $list.ItemsSource = $addresses
    Write-QOSettingsUILog ("Bound list. Count=" + $addresses.Count)

    # Load cutoff date
    try {
        $stored = [string](& $getDateCmd)
        $stored = ($stored + "").Trim()

        if ($stored) {
            $dt = $null
            if ([datetime]::TryParseExact($stored, "yyyy-MM-dd", $null, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
                $txtCutoff.Text = $dt.ToString("dd/MM/yyyy")
                $lblCutoffHint.Text = "Using stored start date. Only emails newer than this will be scanned."
            } else {
                $txtCutoff.Text = (Get-Date).ToString("dd/MM/yyyy")
                $lblCutoffHint.Text = "Stored date was invalid. Using today's date until you choose one."
            }
        } else {
            $txtCutoff.Text = (Get-Date).ToString("dd/MM/yyyy")
            $lblCutoffHint.Text = "Email sync start date will follow today's date until you choose one."
        }
    } catch {
        $txtCutoff.Text = (Get-Date).ToString("dd/MM/yyyy")
        $lblCutoffHint.Text = "Email sync start date will follow today's date until you choose one."
        Write-QOSettingsUILog ("Cutoff init failed: " + $_.Exception.ToString())
    }

    # Unwire old handlers
    try { if ($script:QOSettings_AddHandler) { $btnAdd.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler) } } catch { }
    try { if ($script:QOSettings_RemHandler) { $btnRem.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler) } } catch { }
    try { if ($script:QOSettings_PickDateHandler) { $btnPick.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_PickDateHandler) } } catch { }

    # Add address
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

    # Remove address
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
            if ($hint) { $hint.Text = "Remove failed. Check logs." }
        }
    }.GetNewClosure()

    # Pick cutoff date
    $script:QOSettings_PickDateHandler = [System.Windows.RoutedEventHandler]{
        try {
            $initial = Get-Date
            $stored = ""
            try { $stored = ([string](& $getDateCmd)).Trim() } catch { $stored = "" }

            if ($stored) {
                $tmp = $null
                if ([datetime]::TryParseExact($stored, "yyyy-MM-dd", $null, [System.Globalization.DateTimeStyles]::None, [ref]$tmp)) {
                    $initial = $tmp.Date
                }
            }

            $picked = Show-QODatePickerFlyout -InitialDate $initial
            if (-not $picked) { return }

            $iso = $picked.ToString("yyyy-MM-dd")
            $null = & $setDateCmd -DateString $iso

            $txtCutoff.Text = $picked.ToString("dd/MM/yyyy")
            $lblCutoffHint.Text = "Using stored start date. Only emails newer than this will be scanned."
            if ($hint) { $hint.Text = "Saved start date: " + $picked.ToString("dd/MM/yyyy") }

            Write-QOSettingsUILog ("Cutoff saved: " + $iso)
        }
        catch {
            Write-QOSettingsUILog ("Pick date failed: " + $_.Exception.ToString())
            if ($hint) { $hint.Text = "Date picker failed. Check logs." }
        }
    }.GetNewClosure()

    # Wire handlers
    $btnAdd.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
    $btnRem.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)
    $btnPick.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_PickDateHandler)

    Write-QOSettingsUILog "Wired handlers using AddHandler"
    return $root
}

Export-ModuleMember -Function New-QOTSettingsView, Write-QOSettingsUILog
