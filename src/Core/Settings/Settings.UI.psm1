# Settings.UI.psm1
# Settings page UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Tickets.psm1")  -Force -ErrorAction SilentlyContinue

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
        $BtnCheck,
        $ListBox,
        $HintText
    )

    $EmailBox.IsEnabled  = $Enabled
    $BtnAdd.IsEnabled    = $Enabled
    $BtnRemove.IsEnabled = $Enabled
    $BtnCheck.IsEnabled  = $Enabled
    $ListBox.IsEnabled   = $Enabled

    $opacity = if ($Enabled) { 1 } else { 0.55 }
    $EmailBox.Opacity = $opacity
    $ListBox.Opacity  = $opacity
    $HintText.Opacity = $opacity
    $BtnCheck.Opacity = $opacity
}

function Initialize-QOSettingsUI {
    param([Parameter(Mandatory)] $Window)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $settings = Get-QOSettings

    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent

    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" })) | Out-Null
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" }))    | Out-Null

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.Margin = "0,0,0,10"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    $grid.Children.Add($title) | Out-Null

    $panel = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetRow($panel, 1)
    $grid.Children.Add($panel) | Out-Null

    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.Text = "Ticketing"
    $hdr.FontSize = 14
    $hdr.FontWeight = "SemiBold"
    $hdr.Foreground = [System.Windows.Media.Brushes]::White
    $hdr.Margin = "0,0,0,8"
    $panel.Children.Add($hdr) | Out-Null

    $chkEnable = New-Object System.Windows.Controls.CheckBox
    $chkEnable.Content = "Enable email to ticket creation"
    $chkEnable.IsChecked = [bool]$settings.Tickets.EmailIntegration.Enabled
    $chkEnable.Foreground = [System.Windows.Media.Brushes]::White
    $chkEnable.Margin = "0,0,0,10"
    $panel.Children.Add($chkEnable) | Out-Null

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = "Horizontal"
    $row.Margin = "0,0,0,8"

    $emailBox = New-Object System.Windows.Controls.TextBox
    $emailBox.Width = 320
    $emailBox.Margin = "0,0,8,0"
    $emailBox.Background  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $emailBox.Foreground  = [System.Windows.Media.Brushes]::White
    $emailBox.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
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

    $btnCheck = New-Object System.Windows.Controls.Button
    $btnCheck.Content = "Check email now"
    $btnCheck.Width = 160
    $btnCheck.Margin = "0,0,0,8"
    $panel.Children.Add($btnCheck) | Out-Null

    $list = New-Object System.Windows.Controls.ListBox
    $list.MinHeight = 140
    $list.Background  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $list.Foreground  = [System.Windows.Media.Brushes]::White
    $list.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
    $panel.Children.Add($list) | Out-Null

    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = "Add one or more mailbox addresses. Automatic email polling will be added later."
    $hint.Margin = "0,8,0,0"
    $hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    $panel.Children.Add($hint) | Out-Null

    Refresh-MonitoredList -ListBox $list

    Set-EmailControlsEnabledState `
        -Enabled ([bool]$chkEnable.IsChecked) `
        -EmailBox $emailBox `
        -BtnAdd $btnAdd `
        -BtnRemove $btnRemove `
        -BtnCheck $btnCheck `
        -ListBox $list `
        -HintText $hint

    $chkEnable.Add_Checked({
        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.Enabled = $true
        Save-QOSettings -Settings $s
        Set-EmailControlsEnabledState $true $emailBox $btnAdd $btnRemove $btnCheck $list $hint
    })

    $chkEnable.Add_Unchecked({
        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.Enabled = $false
        Save-QOSettings -Settings $s
        Set-EmailControlsEnabledState $false $emailBox $btnAdd $btnRemove $btnCheck $list $hint
    })

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

    $btnRemove.Add_Click({
        $sel = $list.SelectedItem
        if (-not $sel) { return }

        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.MonitoredAddresses = @(
            @($s.Tickets.EmailIntegration.MonitoredAddresses) |
            Where-Object { "$_" -ne "$sel" }
        )

        Save-QOSettings -Settings $s
        Refresh-MonitoredList -ListBox $list
    })

    $btnCheck.Add_Click({
        try {
            if (Get-Command Invoke-QOEmailTicketPoll -ErrorAction SilentlyContinue) {
                $null = @(Invoke-QOEmailTicketPoll)
            }
            if (Get-Command Update-QOTicketsGrid -ErrorAction SilentlyContinue) {
                Update-QOTicketsGrid
            }
        } catch {}
    })

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
