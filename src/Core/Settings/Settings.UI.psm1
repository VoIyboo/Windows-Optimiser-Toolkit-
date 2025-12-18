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

    $raw = Get-Content -LiteralPath $xamlPath -Raw

    # Convert Window XAML into a hosted Grid:
    # 1) Replace <Window ...> with <Grid ...>
    # 2) Strip Window-only attributes (Title, Height, Width, Topmost, etc)
    # 3) Rename <Window.Resources> to <Grid.Resources>
    # 4) Replace closing </Window> with </Grid>

    $raw = $raw -replace '^\s*<Window\b', '<Grid'

    # Remove common Window-only attributes from the root element
    $raw = $raw -replace '\s+Title="[^"]*"', ''
    $raw = $raw -replace '\s+Height="[^"]*"', ''
    $raw = $raw -replace '\s+Width="[^"]*"', ''
    $raw = $raw -replace '\s+Topmost="[^"]*"', ''
    $raw = $raw -replace '\s+WindowStartupLocation="[^"]*"', ''
    $raw = $raw -replace '\s+ResizeMode="[^"]*"', ''
    $raw = $raw -replace '\s+SizeToContent="[^"]*"', ''
    $raw = $raw -replace '\s+ShowInTaskbar="[^"]*"', ''
    $raw = $raw -replace '\s+WindowStyle="[^"]*"', ''
    $raw = $raw -replace '\s+AllowsTransparency="[^"]*"', ''

    # Property element rename for resources
    $raw = $raw -replace '<Window\.Resources>', '<Grid.Resources>'
    $raw = $raw -replace '</Window\.Resources>', '</Grid.Resources>'

    # Close tag rename
    $raw = $raw -replace '</Window>\s*$', '</Grid>'

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$raw)
    $root = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $root) {
        throw "Failed to load Settings view from SettingsWindow.xaml"
    }

    # Find controls
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
        $emails = @($s.Tickets.EmailIntegration.MonitoredAddresses)

        foreach ($e in $emails) {
            [void]$list.Items.Add([string]$e)
        }
    }

    Refresh-List

    $btnAdd.Add_Click({
        try {
            $addr = ($txtEmail.Text + "").Trim()
            if (-not $addr) { $hint.Text = "Enter an email address."; return }

            $s = Ensure-SettingsShape
            $current = @($s.Tickets.EmailIntegration.MonitoredAddresses)

            if ($current -contains $addr) {
                $hint.Text = "Already exists."
                return
            }

            $s.Tickets.EmailIntegration.MonitoredAddresses = @($current + $addr)
            Save-QOSettings -Settings $s

            $txtEmail.Text = ""
            $hint.Text = "Added $addr"
            Refresh-List
        }
        catch {
            $hint.Text = "Add failed. Check logs."
        }
    })

    $btnRem.Add_Click({
        try {
            $sel = $list.SelectedItem
            if (-not $sel) { $hint.Text = "Select an address."; return }

            $s = Ensure-SettingsShape

            $s.Tickets.EmailIntegration.MonitoredAddresses =
                @($s.Tickets.EmailIntegration.MonitoredAddresses | Where-Object { $_ -ne $sel })

            Save-QOSettings -Settings $s
            $hint.Text = "Removed $sel"
            Refresh-List
        }
        catch {
            $hint.Text = "Remove failed. Check logs."
        }
    })

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
