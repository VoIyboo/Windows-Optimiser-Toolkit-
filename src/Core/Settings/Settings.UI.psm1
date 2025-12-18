# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside the main window, no popups)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

function New-QOTSettingsView {
    param([Parameter(Mandatory)] $Window)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "SettingsWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) { throw "SettingsWindow.xaml not found at $xamlPath" }

    # Convert root <Window> to <Grid> so it can be hosted
    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $win = $doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") { throw "SettingsWindow.xaml root must be <Window>." }

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
            foreach ($rChild in @($child.ChildNodes)) { $null = $newRes.AppendChild($rChild.Clone()) }
            $null = $grid.AppendChild($newRes)
        } else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $doc.RemoveChild($win)
    $null = $doc.AppendChild($grid)

    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root   = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load Settings view from SettingsWindow.xaml" }

    function Find-QONode($r, [string]$n) {
        [System.Windows.LogicalTreeHelper]::FindLogicalNode($r, $n)
    }

    $txtEmail = Find-QONode $root "TxtEmail"
    $btnAdd   = Find-QONode $root "BtnAdd"
    $btnRem   = Find-QONode $root "BtnRemove"
    $list     = Find-QONode $root "LstEmails"
    $hint     = Find-QONode $root "LblHint"

    if (-not $txtEmail) { throw "TxtEmail not found" }
    if (-not $btnAdd)   { throw "BtnAdd not found" }
    if (-not $btnRem)   { throw "BtnRemove not found" }
    if (-not $list)     { throw "LstEmails not found" }
    if (-not $hint)     { throw "LblHint not found" }

    function Set-Hint([AllowEmptyString()][string]$t) {
        try {
            if ($hint -is [System.Windows.Controls.TextBlock]) { $hint.Text = $t; return }
            if ($hint.PSObject.Properties.Match("Text").Count -gt 0) { $hint.Text = $t; return }
            if ($hint.PSObject.Properties.Match("Content").Count -gt 0) { $hint.Content = $t; return }
        } catch { }
    }

    function Ensure-SettingsShape {
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

    function Refresh-List {
        $list.Items.Clear()
        $s = Ensure-SettingsShape
        foreach ($e in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
            [void]$list.Items.Add([string]$e)
        }
    }

    Refresh-List
    Set-Hint ""

    $btnAdd.Add_Click({
        try {
            $addr = ($txtEmail.Text + "").Trim()
            if (-not $addr) { Set-Hint "Enter an email address."; return }

            $s = Ensure-SettingsShape
            $current = @($s.Tickets.EmailIntegration.MonitoredAddresses)

            if ($current -contains $addr) { Set-Hint "Already exists."; return }

            $s.Tickets.EmailIntegration.MonitoredAddresses = @($current + $addr)
            Save-QOSettings -Settings $s

            $txtEmail.Text = ""
            Set-Hint "Added $addr"
            Refresh-List
        } catch {
            Set-Hint ("Add failed: " + $_.Exception.Message)
        }
    })

    $btnRem.Add_Click({
        try {
            $sel = $list.SelectedItem
            if (-not $sel) { Set-Hint "Select an address."; return }

            $s = Ensure-SettingsShape
            $s.Tickets.EmailIntegration.MonitoredAddresses =
                @($s.Tickets.EmailIntegration.MonitoredAddresses | Where-Object { $_ -ne $sel })

            Save-QOSettings -Settings $s
            Set-Hint "Removed $sel"
            Refresh-List
        } catch {
            Set-Hint ("Remove failed: " + $_.Exception.Message)
        }
    })

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
