# Settings.UI.psm1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop

function Initialize-QOSettingsUI {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) {
        throw "Settings UI: Get-QOSettings not available. Core Settings.psm1 did not import."
    }
    if (-not (Get-Command Save-QOSettings -ErrorAction SilentlyContinue)) {
        throw "Settings UI: Save-QOSettings not available. Core Settings.psm1 did not import."
    }

    # Root container
    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent
    $root.Padding = "0"

    # Layout grid
    $grid = New-Object System.Windows.Controls.Grid
    $null = $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    $null = $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" }))

    # Title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.Margin = "0,0,0,10"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    $null = $grid.Children.Add($title)

    # Ensure settings shape exists
    $settings = Get-QOSettings

    if (-not $settings.Tickets) {
        $settings | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $settings.Tickets.EmailIntegration) {
        $settings.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue (
            [pscustomobject]@{ Enabled = $false; MonitoredAddresses = @() }
        ) -Force
    }
    if ($null -eq $settings.Tickets.EmailIntegration.MonitoredAddresses) {
        $settings.Tickets.EmailIntegration.MonitoredAddresses = @()
    }

    # Panel
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = "0,0,0,0"
    [System.Windows.Controls.Grid]::SetRow($panel, 1)

    $ticketTitle = New-Object System.Windows.Controls.TextBlock
    $ticketTitle.Text = "Ticketing"
    $ticketTitle.FontSize = 14
    $ticketTitle.FontWeight = "SemiBold"
    $ticketTitle.Foreground = [System.Windows.Media.Brushes]::White
    $ticketTitle.Margin = "0,0,0,8"
    $null = $panel.Children.Add($ticketTitle)

    $chkEnable = New-Object System.Windows.Controls.CheckBox
    $chkEnable.Content = "Enable email to ticket creation"
    $chkEnable.IsChecked = [bool]$settings.Tickets.EmailIntegration.Enabled
    $chkEnable.Foreground = [System.Windows.Media.Brushes]::White
    $chkEnable.Margin = "0,0,0,10"
    $null = $panel.Children.Add($chkEnable)

    $inputRow = New-Object System.Windows.Controls.StackPanel
    $inputRow.Orientation = "Horizontal"
    $inputRow.Margin = "0,0,0,8"

    $emailBox = New-Object System.Windows.Controls.TextBox
    $emailBox.Width = 320
    $emailBox.Margin = "0,0,8,0"
    $emailBox.Text = ""
    $null = $inputRow.Children.Add($emailBox)

    $btnAdd = New-Object System.Windows.Controls.Button
    $btnAdd.Content = "Add"
    $btnAdd.Width = 90
    $null = $inputRow.Children.Add($btnAdd)

    $null = $panel.Children.Add($inputRow)

    $list = New-Object System.Windows.Controls.ListBox
    $list.MinHeight = 140
    $null = $panel.Children.Add($list)

    function Refresh-MonitoredList {
        param([Parameter(Mandatory)]$ListBox)

        $ListBox.Items.Clear()
        $s = Get-QOSettings

        foreach ($addr in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
            if ($addr) { [void]$ListBox.Items.Add($addr) }
        }
    }

    Refresh-MonitoredList -ListBox $list

    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = "Add one or more mailbox addresses. Automatic email polling will be added later."
    $hint.Margin = "0,8,0,0"
    $hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    $null = $panel.Children.Add($hint)

    $null = $grid.Children.Add($panel)

    # Events and persistence
    $chkEnable.Add_Checked({
        $s = Get-QOSettings
        if (-not $s.Tickets) { $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force }
        if (-not $s.Tickets.EmailIntegration) {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue (
                [pscustomobject]@{ Enabled = $false; MonitoredAddresses = @() }
            ) -Force
        }

        $s.Tickets.EmailIntegration.Enabled = $true
        Save-QOSettings -Settings $s
        Refresh-MonitoredList -ListBox $list
    })

    $chkEnable.Add_Unchecked({
        $s = Get-QOSettings
        if (-not $s.Tickets) { $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force }
        if (-not $s.Tickets.EmailIntegration) {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue (
                [pscustomobject]@{ Enabled = $false; MonitoredAddresses = @() }
            ) -Force
        }

        $s.Tickets.EmailIntegration.Enabled = $false
        Save-QOSettings -Settings $s
        Refresh-MonitoredList -ListBox $list
    })

    $btnAdd.Add_Click({
        $addr = ($emailBox.Text | ForEach-Object { $_.Trim() })
        if ([string]::IsNullOrWhiteSpace($addr)) { return }

        $s = Get-QOSettings
        if (-not $s.Tickets) { $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force }
        if (-not $s.Tickets.EmailIntegration) {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue (
                [pscustomobject]@{ Enabled = $false; MonitoredAddresses = @() }
            ) -Force
        }
        if ($null -eq $s.Tickets.EmailIntegration.MonitoredAddresses) {
            $s.Tickets.EmailIntegration.MonitoredAddresses = @()
        }

        if ($s.Tickets.EmailIntegration.MonitoredAddresses -notcontains $addr) {
            $s.Tickets.EmailIntegration.MonitoredAddresses += $addr
            Save-QOSettings -Settings $s
        }

        $emailBox.Text = ""
        Refresh-MonitoredList -ListBox $list
    })

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
