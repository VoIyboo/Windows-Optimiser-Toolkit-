# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside the main window, no popups)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

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

    # ------------------------------------------------------------
    # Convert SettingsWindow.xaml root <Window> to <Grid> safely
    # ------------------------------------------------------------
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

    if (-not $root) {
        throw "Failed to load Settings view from SettingsWindow.xaml"
    }

    # ------------------------------------------------------------
    # Controls
    # ------------------------------------------------------------
    $txtEmail = $root.FindName("TxtEmail")
    $btnAdd   = $root.FindName("BtnAdd")
    $btnRem   = $root.FindName("BtnRemove")
    $list     = $root.FindName("LstEmails")
    $hint     = $root.FindName("LblHint")

    if (-not $txtEmail) { throw "TxtEmail not found in SettingsWindow.xaml" }
    if (-not $btnAdd)   { throw "BtnAdd not found in SettingsWindow.xaml" }
    if (-not $btnRem)   { throw "BtnRemove not found in SettingsWindow.xaml" }
    if (-not $list)     { throw "LstEmails not found in SettingsWindow.xaml" }
    if (-not $hint)     { throw "LblHint not found in SettingsWindow.xaml" }

    # ------------------------------------------------------------
    # Delegate for hint text (always invokable, even in WPF handlers)
    # ------------------------------------------------------------
    $SetHint = [System.Action[string]]{
        param([string]$Value)

        if ($null -eq $hint) { return }

        if ($hint.PSObject.Properties.Match("Text").Count -gt 0) {
            $hint.Text = $Value
            return
        }

        if ($hint.PSObject.Properties.Match("Content").Count -gt 0) {
            $hint.Content = $Value
            return
        }
    }

    # ------------------------------------------------------------
    # Settings helpers
    # ------------------------------------------------------------
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
    $SetHint.Invoke("")

    # ------------------------------------------------------------
    # Events
    # ------------------------------------------------------------
    $btnAdd.Add_Click({
        try {
            $addr = ($txtEmail.Text + "").Trim()
            if (-not $addr) {
                $SetHint.Invoke("Enter an email address.")
                return
            }

            $s = Ensure-SettingsShape
            $current = @($s.Tickets.EmailIntegration.MonitoredAddresses)

            if ($current -contains $addr) {
                $SetHint.Invoke("Already exists.")
                return
            }

            $s.Tickets.EmailIntegration.MonitoredAddresses = @($current + $addr)
            Save-QOSettings -Settings $s

            $txtEmail.Text = ""
            $SetHint.Invoke("Added $addr")
            Refresh-List
        }
        catch {
            $SetHint.Invoke("Add failed. Check logs.")
        }
    })

    $btnRem.Add_Click({
        try {
            $sel = $list.SelectedItem
            if (-not $sel) {
                $SetHint.Invoke("Select an address.")
                return
            }

            $s = Ensure-SettingsShape
            $s.Tickets.EmailIntegration.MonitoredAddresses =
                @($s.Tickets.EmailIntegration.MonitoredAddresses | Where-Object { $_ -ne $sel })

            Save-QOSettings -Settings $s
            $SetHint.Invoke("Removed $sel")
            Refresh-List
        }
        catch {
            $SetHint.Invoke("Remove failed. Check logs.")
        }
    })

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
