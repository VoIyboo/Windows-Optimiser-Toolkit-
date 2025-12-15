# Settings.UI.psm1
# Settings page UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Tickets.psm1")  -Force -ErrorAction SilentlyContinue

function Refresh-MonitoredList {
    param([Parameter(Mandatory)] $ListBox)

    $ListBox.Items.Clear()

    $s = Get-QOSettings
    if ($s -and $s.Tickets -and $s.Tickets.EmailIntegration -and $s.Tickets.EmailIntegration.MonitoredAddresses) {
        foreach ($addr in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
            if ($addr) { [void]$ListBox.Items.Add([string]$addr) }
        }
    }
}

function Set-EmailControlsEnabledState {
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)]$EmailBox,
        [Parameter(Mandatory)]$BtnAdd,
        [Parameter(Mandatory)]$BtnRemove,
        [Parameter(Mandatory)]$BtnCheck,
        [Parameter(Mandatory)]$ListBox,
        [Parameter(Mandatory)]$HintText
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
}

function Initialize-QOSettingsUI {
    param([Parameter(Mandatory)] $Window)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $settings = Get-QOSettings

    # Root
    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent

    # Grid
    $grid = New-Object System.Windows.Controls.Grid
    [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" }))

    # Title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.Margin = "0,0,0,10"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    [void]$grid.Children.Add($title)

    # Panel
    $panel = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetRow($panel, 1)
    [void]$grid.Children.Add($panel)

    # Section header
    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.Text = "Ticketing"
    $hdr.FontSize = 14
    $hdr.FontWeight = "SemiBold"
    $hdr.Foreground = [System.Windows.Media.Brushes]::White
    $hdr.Margin = "0,0,0,8"
    [void]$panel.Children.Add($hdr)

    # Enable checkbox
    $chkEnable = New-Object System.Windows.Controls.CheckBox
    $chkEnable.Content = "Enable email to ticket creation"
    $chkEnable.IsChecked = [bool]$settings.Tickets.EmailIntegration.Enabled
    $chkEnable.Foreground = [System.Windows.Media.Brushes]::White
    $chkEnable.Margin = "0,0,0,10"
    [void]$panel.Children.Add($chkEnable)

    # Input row
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = "Horizontal"
    $row.Margin = "0,0,0,8"

    $emailBox = New-Object System.Windows.Controls.TextBox
    $emailBox.Width = 320
    $emailBox.Margin = "0,0,8,0"
    $emailBox.Background  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $emailBox.Foreground  = [System.Windows.Media.Brushes]::White
    $emailBox.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
    [void]$row.Children.Add($emailBox)

    $btnAdd = New-Object System.Windows.Controls.Button
    $btnAdd.Content = "Add"
    $btnAdd.Width = 90
    $btnAdd.Margin = "0,0,8,0"
    [void]$row.Children.Add($btnAdd)

    $btnRemove = New-Object System.Windows.Controls.Button
    $btnRemove.Content = "Remove"
    $btnRemove.Width = 90
    [void]$row.Children.Add($btnRemove)

    [void]$panel.Children.Add($row)

    # Check email now button
    $btnCheck = New-Object System.Windows.Controls.Button
    $btnCheck.Content = "Check email now"
    $btnCheck.Width = 160
    $btnCheck.Margin = "0,0,0,8"
    [void]$panel.Children.Add($btnCheck)

    # List
    $list = New-Object System.Windows.Controls.ListBox
    $list.MinHeight = 140
    $list.Background  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $list.Foreground  = [System.Windows.Media.Brushes]::White
    $list.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
    [void]$panel.Children.Add($list)

    # Hint
    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = "Add one or more mailbox addresses. Automatic email polling will be added later."
    $hint.Margin = "0,8,0,0"
    $hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    [void]$panel.Children.Add($hint)

    # Initial load list + state
    Refresh-MonitoredList -ListBox $list

    Set-EmailControlsEnabledState `
        -Enabled ([bool]$chkEnable.IsChecked) `
        -EmailBox $emailBox `
        -BtnAdd $btnAdd `
        -BtnRemove $btnRemove `
        -BtnCheck $btnCheck `
        -ListBox $list `
        -HintText $hint

    # Checkbox handlers
    $chkEnable.Add_Checked({
        try {
            $s = Get-QOSettings
            if (-not $s.Tickets) { $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force }
            if (-not $s.Tickets.EmailIntegration) { $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force }
            if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "Enabled")) {
                $s.Tickets.EmailIntegration | Add-Member -NotePropertyName Enabled -NotePropertyValue $true -Force
            } else {
                $s.Tickets.EmailIntegration.Enabled = $true
            }
            Save-QOSettings -Settings $s
        } catch {}

        Set-EmailControlsEnabledState $true $emailBox $btnAdd $btnRemove $btnCheck $list $hint
    })

    $chkEnable.Add_Unchecked({
        try {
            $s = Get-QOSettings
            if (-not $s.Tickets) { $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force }
            if (-not $s.Tickets.EmailIntegration) { $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force }
            if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "Enabled")) {
                $s.Tickets.EmailIntegration | Add-Member -NotePropertyName Enabled -NotePropertyValue $false -Force
            } else {
                $s.Tickets.EmailIntegration.Enabled = $false
            }
            Save-QOSettings -Settings $s
        } catch {}

        Set-EmailControlsEnabledState $false $emailBox $btnAdd $btnRemove $btnCheck $list $hint
    })

    # ADD
    $btnAdd.Add_Click({
        try {
            $addr = [string]$emailBox.Text
            if ($null -eq $addr) { $addr = "" }
            $addr = $addr.Trim()

            if ([string]::IsNullOrWhiteSpace($addr)) { return }
            if ($addr -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return }

            $s = Get-QOSettings

            if (-not $s.Tickets) {
                $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if (-not $s.Tickets.EmailIntegration) {
                $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses")) {
                $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
            }

            $s.Tickets.EmailIntegration.MonitoredAddresses = @($s.Tickets.EmailIntegration.MonitoredAddresses)

            if ($s.Tickets.EmailIntegration.MonitoredAddresses -notcontains $addr) {
                $s.Tickets.EmailIntegration.MonitoredAddresses += $addr
            }

            Save-QOSettings -Settings $s

            $emailBox.Text = ""
            Refresh-MonitoredList -ListBox $list
        }
        catch { }
    })

    # REMOVE
    $btnRemove.Add_Click({
        try {
            $sel = $list.SelectedItem
            if (-not $sel) { return }

            $s = Get-QOSettings
            if (-not $s.Tickets -or -not $s.Tickets.EmailIntegration) { return }
            if (-not $s.Tickets.EmailIntegration.MonitoredAddresses) { return }

            $s.Tickets.EmailIntegration.MonitoredAddresses = @(
                @($s.Tickets.EmailIntegration.MonitoredAddresses) | Where-Object { "$_" -ne "$sel" }
            )

            Save-QOSettings -Settings $s
            Refresh-MonitoredList -ListBox $list
        }
        catch { }
    })

    # CHECK EMAIL NOW
    $btnCheck.Add_Click({
        try {
            if (Get-Command Invoke-QOEmailTicketPoll -ErrorAction SilentlyContinue) {
                Invoke-QOEmailTicketPoll | Out-Null
            }
            if (Get-Command Update-QOTicketsGrid -ErrorAction SilentlyContinue) {
                Update-QOTicketsGrid
            }
        } catch { }
    })

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
