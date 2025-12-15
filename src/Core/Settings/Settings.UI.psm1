# Settings.UI.psm1
# Settings page UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop

function Refresh-MonitoredList {
    param([Parameter(Mandatory)] $ListBox)

    $ListBox.Items.Clear()

    $s = Get-QOSettings
    if ($s.Tickets -and $s.Tickets.EmailIntegration -and $s.Tickets.EmailIntegration.MonitoredAddresses) {
        foreach ($addr in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
            if ($addr) { [void]$ListBox.Items.Add($addr) }
        }
    }
}

function Set-EmailControlsEnabledState {
    param(
        [bool]$Enabled,
        $EmailBox,
        $BtnAdd,
        $BtnRemove,
        $ListBox,
        $HintText
    )

    $EmailBox.IsEnabled = $Enabled
    $BtnAdd.IsEnabled = $Enabled
    $BtnRemove.IsEnabled = $Enabled
    $ListBox.IsEnabled = $Enabled

    $opacity = if ($Enabled) { 1 } else { 0.55 }
    $EmailBox.Opacity = $opacity
    $ListBox.Opacity  = $opacity
    $HintText.Opacity = $opacity
}

function Initialize-QOSettingsUI {
    param([Parameter(Mandatory)] $Window)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $settings = Get-QOSettings

    # Root
    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent

    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" })) | Out-Null
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" })) | Out-Null

    # Title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.Margin = "0,0,0,10"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    $grid.Children.Add($title) | Out-Null

    # Panel
    $panel = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetRow($panel, 1)
    $grid.Children.Add($panel) | Out-Null

    # Section header
    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.Text = "Ticketing"
    $hdr.FontSize = 14
    $hdr.FontWeight = "SemiBold"
    $hdr.Foreground = [System.Windows.Media.Brushes]::White
    $hdr.Margin = "0,0,0,8"
    $panel.Children.Add($hdr) | Out-Null

    # Enable checkbox
    $chkEnable = New-Object System.Windows.Controls.CheckBox
    $chkEnable.Content = "Enable email to ticket creation"
    $chkEnable.IsChecked = [bool]$settings.Tickets.EmailIntegration.Enabled
    $chkEnable.Foreground = [System.Windows.Media.Brushes]::White
    $chkEnable.Margin = "0,0,0,10"
    $panel.Children.Add($chkEnable) | Out-Null

    # Input row
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = "Horizontal"
    $row.Margin = "0,0,0,8"

    $emailBox = New-Object System.Windows.Controls.TextBox
    $emailBox.Width = 320
    $emailBox.Margin = "0,0,8,0"
    $row.Children.Add($emailBox) | Out-Null

    $btnAdd = New-Object System.Windows.Controls.Button
    $btnAdd.Content = "Add"
    $btnAdd.Width = 90
    $btnAdd.Margin = "0,0,8,0"
    $row.Children.Add($btnAdd) | Out-Null

    $btnRemove = New-Object System.Windows.Controls.Button
    $btnRemove.Content = "Remove"
    $btnRemove.Width = 90
    $row.Children.Add($btnRemove) | Out-Null

    $panel.Children.Add($row) | Out-Null

    # List
    $list = New-Object System.Windows.Controls.ListBox
    $list.MinHeight = 140
    $panel.Children.Add($list) | Out-Null

    # Hint
    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = "Add one or more mailbox addresses. Automatic email polling will be added later."
    $hint.Margin = "0,8,0,0"
    $hint.Foreground = [System.Windows.Media.Brushes]::Gray
    $panel.Children.Add($hint) | Out-Null

    Refresh-MonitoredList -ListBox $list

    Set-EmailControlsEnabledState `
        -Enabled ([bool]$chkEnable.IsChecked) `
        -EmailBox $emailBox `
        -BtnAdd $btnAdd `
        -BtnRemove $btnRemove `
        -ListBox $list `
        -HintText $hint

    # Checkbox handlers
    $chkEnable.Add_Checked({
        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.Enabled = $true
        Save-QOSettings -Settings $s
        Set-EmailControlsEnabledState $true $emailBox $btnAdd $btnRemove $list $hint
    })

    $chkEnable.Add_Unchecked({
        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.Enabled = $false
        Save-QOSettings -Settings $s
        Set-EmailControlsEnabledState $false $emailBox $btnAdd $btnRemove $list $hint
    })

    # ADD
$btnAdd.Add_Click({
    $addr = $emailBox.Text
    if ($null -eq $addr) { $addr = "" }
    $addr = $addr.Trim()

    if ($addr -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return }

    $s = Get-QOSettings
    if ($s.Tickets.EmailIntegration.MonitoredAddresses -notcontains $addr) {
        $s.Tickets.EmailIntegration.MonitoredAddresses += $addr
        Save-QOSettings -Settings $s
    }

    $emailBox.Text = ""
    Refresh-MonitoredList -ListBox $list
})

    # REMOVE
    $btnRemove.Add_Click({
        $sel = $list.SelectedItem
        if (-not $sel) { return }

        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.MonitoredAddresses = @(
            $s.Tickets.EmailIntegration.MonitoredAddresses |
            Where-Object { $_ -ne $sel }
        )

        Save-QOSettings -Settings $s
        Refresh-MonitoredList -ListBox $list
    })

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
