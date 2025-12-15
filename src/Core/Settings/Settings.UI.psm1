# Settings.UI.psm1
# Settings page UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Import core settings and helper functions:
# Get-QOSettings, Save-QOSettings
# Add-QOMonitoredEmailAddress, Remove-QOMonitoredEmailAddress, Get-QOMonitoredEmailAddresses, Test-QOEmailAddress
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop

function Refresh-MonitoredList {
    param(
        [Parameter(Mandatory)]
        $ListBox
    )

    # Reload from core each time so the UI always reflects the saved file
    $ListBox.Items.Clear()

    if (Get-Command Get-QOMonitoredEmailAddresses -ErrorAction SilentlyContinue) {
        foreach ($addr in @(Get-QOMonitoredEmailAddresses)) {
            if ($addr) { [void]$ListBox.Items.Add($addr) }
        }
        return
    }

    # Fallback: if helpers do not exist for some reason, do a minimal read
    $s = Get-QOSettings
    if ($s.Tickets -and $s.Tickets.EmailIntegration -and $s.Tickets.EmailIntegration.MonitoredAddresses) {
        foreach ($addr in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
            if ($addr) { [void]$ListBox.Items.Add($addr) }
        }
    }
}

function Set-EmailControlsEnabledState {
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled,

        [Parameter(Mandatory)]
        $EmailBox,

        [Parameter(Mandatory)]
        $BtnAdd,

        [Parameter(Mandatory)]
        $BtnRemove,

        [Parameter(Mandatory)]
        $ListBox,

        [Parameter(Mandatory)]
        $HintText
    )

    # Disable or enable input controls
    $EmailBox.IsEnabled = $Enabled
    $BtnAdd.IsEnabled = $Enabled
    $BtnRemove.IsEnabled = $Enabled
    $ListBox.IsEnabled = $Enabled

    # Visual hinting: dim text when disabled
    if ($Enabled) {
        $HintText.Opacity = 1
        $EmailBox.Opacity = 1
        $ListBox.Opacity = 1
    }
    else {
        $HintText.Opacity = 0.55
        $EmailBox.Opacity = 0.55
        $ListBox.Opacity = 0.55
    }
}

function Initialize-QOSettingsUI {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Sanity check that core settings functions are available
    if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) {
        throw "Settings UI: Get-QOSettings not available. Core Settings.psm1 did not import."
    }

    # Root container for the settings page
    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent
    $root.Padding = "0"

    # Layout grid
    $grid = New-Object System.Windows.Controls.Grid
    [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" }))

    # Page title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.Margin = "0,0,0,10"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    [void]$grid.Children.Add($title)

    # Main settings panel
    $panel = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetRow($panel, 1)
    [void]$grid.Children.Add($panel)

    # Load settings once for initial state
    $settings = Get-QOSettings

    # Section title
    $ticketTitle = New-Object System.Windows.Controls.TextBlock
    $ticketTitle.Text = "Ticketing"
    $ticketTitle.FontSize = 14
    $ticketTitle.FontWeight = "SemiBold"
    $ticketTitle.Foreground = [System.Windows.Media.Brushes]::White
    $ticketTitle.Margin = "0,0,0,8"
    [void]$panel.Children.Add($ticketTitle)

    # Enable email integration checkbox
    $chkEnable = New-Object System.Windows.Controls.CheckBox
    $chkEnable.Content = "Enable email to ticket creation"
    $chkEnable.IsChecked = [bool]$settings.Tickets.EmailIntegration.Enabled
    $chkEnable.Foreground = [System.Windows.Media.Brushes]::White
    $chkEnable.Margin = "0,0,0,10"
    [void]$panel.Children.Add($chkEnable)

    # Input row: email textbox, add, remove
    $inputRow = New-Object System.Windows.Controls.StackPanel
    $inputRow.Orientation = "Horizontal"
    $inputRow.Margin = "0,0,0,8"

    $emailBox = New-Object System.Windows.Controls.TextBox
    $emailBox.Width = 320
    $emailBox.Margin = "0,0,8,0"
    [void]$inputRow.Children.Add($emailBox)

    $btnAdd = New-Object System.Windows.Controls.Button
    $btnAdd.Content = "Add"
    $btnAdd.Width = 90
    $btnAdd.Margin = "0,0,8,0"
    [void]$inputRow.Children.Add($btnAdd)

    $btnRemove = New-Object System.Windows.Controls.Button
    $btnRemove.Content = "Remove"
    $btnRemove.Width = 90
    [void]$inputRow.Children.Add($btnRemove)

    [void]$panel.Children.Add($inputRow)

    # List of monitored addresses
    $list = New-Object System.Windows.Controls.ListBox
    $list.MinHeight = 140
    [void]$panel.Children.Add($list)

    # Hint text
    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = "Add one or more mailbox addresses. Automatic email polling will be added later."
    $hint.Margin = "0,8,0,0"
    $hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    [void]$panel.Children.Add($hint)

    # Populate list initially
    Refresh-MonitoredList -ListBox $list

    # Apply initial enabled or disabled state to controls
    Set-EmailControlsEnabledState `
        -Enabled ([bool]$chkEnable.IsChecked) `
        -EmailBox $emailBox `
        -BtnAdd $btnAdd `
        -BtnRemove $btnRemove `
        -ListBox $list `
        -HintText $hint

    # When checkbox is checked, enable integration and controls
    $chkEnable.Add_Checked({
        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.Enabled = $true
        Save-QOSettings -Settings $s

        Set-EmailControlsEnabledState `
            -Enabled $true `
            -EmailBox $emailBox `
            -BtnAdd $btnAdd `
            -BtnRemove $btnRemove `
            -ListBox $list `
            -HintText $hint
    })

    # When unchecked, disable integration and controls
    $chkEnable.Add_Unchecked({
        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.Enabled = $false
        Save-QOSettings -Settings $s

        Set-EmailControlsEnabledState `
            -Enabled $false `
            -EmailBox $emailBox `
            -BtnAdd $btnAdd `
            -BtnRemove $btnRemove `
            -ListBox $list `
            -HintText $hint
    })

    # Add button: call core helper to validate, dedupe, save
    $btnAdd.Add_Click({
        try {
            $addr = ($emailBox.Text ?? "").Trim()
            if ([string]::IsNullOrWhiteSpace($addr)) { return }

            if (Get-Command Add-QOMonitoredEmailAddress -ErrorAction SilentlyContinue) {
                $added = Add-QOMonitoredEmailAddress -Address $addr
                if ($added) {
                    $emailBox.Text = ""
                    Refresh-MonitoredList -ListBox $list
                }
                return
            }

            # Fallback if helper is missing
            if ($addr -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return }
            $s = Get-QOSettings
            if ($s.Tickets.EmailIntegration.MonitoredAddresses -notcontains $addr) {
                $s.Tickets.EmailIntegration.MonitoredAddresses += $addr
                Save-QOSettings -Settings $s
                $emailBox.Text = ""
                Refresh-MonitoredList -ListBox $list
            }
        }
        catch {
            Write-Host "Add email failed: $($_.Exception.Message)"
        }
    })

    # Remove button: removes selected item from list using core helper
    $btnRemove.Add_Click({
        try {
            $selected = $list.SelectedItem
            if (-not $selected) { return }

            if (Get-Command Remove-QOMonitoredEmailAddress -ErrorAction SilentlyContinue) {
                $removed = Remove-QOMonitoredEmailAddress -Address "$selected"
                if ($removed) {
                    Refresh-MonitoredList -ListBox $list
                }
                return
            }

            # Fallback if helper is missing
            $s = Get-QOSettings
            $s.Tickets.EmailIntegration.MonitoredAddresses = @(
                @($s.Tickets.EmailIntegration.MonitoredAddresses) | Where-Object { "$_".Trim() -ne "$selected".Trim() }
            )
            Save-QOSettings -Settings $s
            Refresh-MonitoredList -ListBox $list
        }
        catch {
            Write-Host "Remove email failed: $($_.Exception.Message)"
        }
    })

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
