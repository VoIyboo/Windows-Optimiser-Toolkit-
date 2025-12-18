# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside MainWindow)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

function Ensure-QOEmailIntegrationSettings {
    $s = Get-QOSettings
    if (-not $s) { $s = [pscustomobject]@{} }

    if (-not ($s.PSObject.Properties.Name -contains "Tickets")) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not ($s.Tickets.PSObject.Properties.Name -contains "EmailIntegration")) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    return $s
}

function Save-QOMonitoredAddressesFromList {
    param(
        [Parameter(Mandatory)] $ListControl
    )

    $s = Ensure-QOEmailIntegrationSettings

    $items = @()
    foreach ($i in $ListControl.Items) {
        $v = ([string]$i).Trim()
        if ($v) { $items += $v }
    }

    $s.Tickets.EmailIntegration.MonitoredAddresses = $items
    Save-QOSettings -Settings $s
}

function Load-QOMonitoredAddressesToList {
    param(
        [Parameter(Mandatory)] $ListControl
    )

    $ListControl.Items.Clear()

    $s = Ensure-QOEmailIntegrationSettings
    foreach ($e in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
        $v = ([string]$e).Trim()
        if ($v) { [void]$ListControl.Items.Add($v) }
    }
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

    # Load XAML as hosted view (convert root Window to Grid)
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

    function Find-QONode {
        param([Parameter(Mandatory)] $Root, [Parameter(Mandatory)] [string] $Name)
        [System.Windows.LogicalTreeHelper]::FindLogicalNode($Root, $Name)
    }

    $txtEmail = Find-QONode -Root $root -Name "TxtEmail"
    $btnAdd   = Find-QONode -Root $root -Name "BtnAdd"
    $btnRem   = Find-QONode -Root $root -Name "BtnRemove"
    $list     = Find-QONode -Root $root -Name "LstEmails"

    if (-not $txtEmail) { throw "TxtEmail not found" }
    if (-not $btnAdd)   { throw "BtnAdd not found" }
    if (-not $btnRem)   { throw "BtnRemove not found" }
    if (-not $list)     { throw "LstEmails not found" }

    # Initial load
    Load-QOMonitoredAddressesToList -ListControl $list

    # Add button: update UI first, then save
    $btnAdd.Add_Click({
        try {
            $addr = ($txtEmail.Text + "").Trim()
            if (-not $addr) { return }

            $exists = $false
            foreach ($i in $list.Items) {
                if (([string]$i).Trim().ToLower() -eq $addr.ToLower()) { $exists = $true; break }
            }

            if (-not $exists) {
                [void]$list.Items.Add($addr)
            }

            $txtEmail.Text = ""
            Save-QOMonitoredAddressesFromList -ListControl $list
        }
        catch {
            # Keep it silent for now. UI already updated.
            # If you want feedback later we can wire LblHint again.
        }
    })

    # Remove button: update UI first, then save
    $btnRem.Add_Click({
        try {
            $sel = $list.SelectedItem
            if (-not $sel) { return }

            $list.Items.Remove($sel)
            Save-QOMonitoredAddressesFromList -ListControl $list
        }
        catch { }
    })

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
