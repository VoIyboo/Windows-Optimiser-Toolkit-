# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside MainWindow)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

function Write-QOSettingsUILog {
    param([string]$Message)

    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $path = Join-Path $logDir "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    }
    catch { }
}

Write-QOSettingsUILog "=== Settings.UI.psm1 LOADED ==="

function Ensure-QOEmailIntegrationSettings {
    $s = Get-QOSettings
    if (-not $s) { $s = [pscustomobject]@{} }

    if (-not ($s.PSObject.Properties.Name -contains "Tickets") -or -not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($s.Tickets.PSObject.Properties.Name -contains "EmailIntegration") -or -not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses") -or $null -eq $s.Tickets.EmailIntegration.MonitoredAddresses) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    return $s
}

function Save-QOMonitoredAddresses {
    param(
        [Parameter(Mandatory)]
        [System.Collections.ObjectModel.ObservableCollection[string]] $Collection
    )

    $s = Ensure-QOEmailIntegrationSettings

    $clean = @(
        $Collection |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ }
    )

    $s.Tickets.EmailIntegration.MonitoredAddresses = $clean
    Save-QOSettings -Settings $s
}

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
        }
        catch { }

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

function New-QOTSettingsView {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "SettingsWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "SettingsWindow.xaml not found at $xamlPath"
    }

    Write-QOSettingsUILog "Loading SettingsWindow.xaml (hosted)"

    # Convert root <Window> to <Grid> so it can be hosted in MainWindow
    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $win = $doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") {
        throw "SettingsWindow.xaml root must be <Window>."
    }

    $ns   = $win.NamespaceURI
    $grid = $doc.CreateElement("Grid", $ns)

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
            $newRes = $doc.CreateElement("Grid.Resources", $ns)
            foreach ($rChild in @($child.ChildNodes)) {
                $null = $newRes.AppendChild($rChild.Clone())
            }
            $null = $grid.AppendChild($newRes)
        }
        else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $doc.RemoveChild($win)
    $null = $doc.AppendChild($grid)

    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root   = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load Settings view from SettingsWindow.xaml" }

    # Controls (real ones, by name and type)
    $txtEmail = Find-QOElementByNameAndType -Root $root -Name "TxtEmail"  -Type ([System.Windows.Controls.TextBox])
    $btnAdd   = Find-QOElementByNameAndType -Root $root -Name "BtnAdd"    -Type ([System.Windows.Controls.Button])
    $btnRem   = Find-QOElementByNameAndType -Root $root -Name "BtnRemove" -Type ([System.Windows.Controls.Button])
    $list     = Find-QOElementByNameAndType -Root $root -Name "LstEmails" -Type ([System.Windows.Controls.ListBox])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }

    Write-QOSettingsUILog ("TxtEmail type=" + $txtEmail.GetType().FullName)
    Write-QOSettingsUILog ("LstEmails type=" + $list.GetType().FullName)

    # Build collection from settings
    $addresses = New-Object 'System.Collections.ObjectModel.ObservableCollection[string]'

    $s = Ensure-QOEmailIntegrationSettings
    foreach ($e in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }

    # Bind list to collection
    $list.ItemsSource = $addresses
    Write-QOSettingsUILog ("Bound list to collection. Count=" + $addresses.Count)

    # IMPORTANT: store the collection on the UI itself (avoids PowerShell scope issues)
    $root.Tag = $addresses
    Write-QOSettingsUILog "Stored addresses on root.Tag"

    # Add
    $btnAdd.Add_Click({
        try {
            $col = $root.Tag
            if (-not $col) { $col = $list.ItemsSource }
            if (-not $col) { throw "Addresses collection missing (root.Tag and list.ItemsSource are null)" }

            $addr = ($txtEmail.Text + "").Trim()
            Write-QOSettingsUILog ("Add clicked. Input='" + $addr + "'")

            if (-not $addr) { return }

            foreach ($x in $col) {
                if (([string]$x).Trim().ToLower() -eq $addr.ToLower()) {
                    $txtEmail.Text = ""
                    Write-QOSettingsUILog "Add ignored (duplicate)"
                    return
                }
            }

            $col.Add($addr)
            $txtEmail.Text = ""

            if ($list.ItemsSource -ne $col) { $list.ItemsSource = $col }

            Save-QOMonitoredAddresses -Collection $col
            Write-QOSettingsUILog "Added + saved"
        }
        catch {
            Write-QOSettingsUILog ("Add failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Add stack: " + $_.ScriptStackTrace)
        }
    })

    # Remove
    $btnRem.Add_Click({
        try {
            $col = $root.Tag
            if (-not $col) { $col = $list.ItemsSource }
            if (-not $col) { throw "Addresses collection missing (root.Tag and list.ItemsSource are null)" }

            $sel = $list.SelectedItem
            Write-QOSettingsUILog ("Remove clicked. Selected='" + ($sel + "") + "'")
            if (-not $sel) { return }

            [void]$col.Remove([string]$sel)

            if ($list.ItemsSource -ne $col) { $list.ItemsSource = $col }

            Save-QOMonitoredAddresses -Collection $col
            Write-QOSettingsUILog "Removed + saved"
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Remove stack: " + $_.ScriptStackTrace)
        }
    })

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
