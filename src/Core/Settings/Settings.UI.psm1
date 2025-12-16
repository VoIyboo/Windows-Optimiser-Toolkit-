# Settings.UI.psm1
# Settings page UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Tickets.psm1")   -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# SAFE CONTROL TEXT SETTER
# Prevents crashes when using Label vs TextBlock vs TextBox
# -------------------------------------------------------------------
function Set-QOTControlTextSafe {
    param(
        [Parameter(Mandatory)] $Control,
        [Parameter(Mandatory)] [string] $Value
    )

    if (-not $Control) { return }

    try {
        # TextBlock / TextBox
        if ($Control -is [System.Windows.Controls.TextBlock] -or
            $Control -is [System.Windows.Controls.TextBox]) {
            $Control.Text = $Value
            return
        }

        # Label / ContentControl
        if ($Control -is [System.Windows.Controls.Label] -or
            $Control -is [System.Windows.Controls.ContentControl]) {
            $Control.Content = $Value
            return
        }

        # Fallback by property existence
        if ($Control.PSObject.Properties.Name -contains 'Text') {
            $Control.Text = $Value
            return
        }
        if ($Control.PSObject.Properties.Name -contains 'Content') {
            $Control.Content = $Value
            return
        }
    }
    catch {
        # Never crash Settings UI
    }
}




function Refresh-MonitoredList {
    param([Parameter(Mandatory)] $ListBox)

    $ListBox.Items.Clear()

    $s = Get-QOSettings

    if ($s -and $s.Tickets -and $s.Tickets.EmailIntegration) {
        foreach ($addr in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
            $a = "$addr".Trim()
            if (-not [string]::IsNullOrWhiteSpace($a)) {
                [void]$ListBox.Items.Add($a)
            }
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

    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent

    $grid = New-Object System.Windows.Controls.Grid
    [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" }))
    [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" }))

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Settings"
    $title.FontSize = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.Margin = "0,0,0,10"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    [void]$grid.Children.Add($title)

    $panel = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetRow($panel, 1)
    [void]$grid.Children.Add($panel)

    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.Text = "Ticketing"
    $hdr.FontSize = 14
    $hdr.FontWeight = "SemiBold"
    $hdr.Foreground = [System.Windows.Media.Brushes]::White
    $hdr.Margin = "0,0,0,8"
    [void]$panel.Children.Add($hdr)

    $chkEnable = New-Object System.Windows.Controls.CheckBox
    $chkEnable.Content = "Enable email to ticket creation"
    $chkEnable.IsChecked = [bool]$settings.Tickets.EmailIntegration.Enabled
    $chkEnable.Foreground = [System.Windows.Media.Brushes]::White
    $chkEnable.Margin = "0,0,0,10"
    [void]$panel.Children.Add($chkEnable)

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

    $btnCheck = New-Object System.Windows.Controls.Button
    $btnCheck.Content = "Check email now"
    $btnCheck.Width = 160
    $btnCheck.Margin = "0,0,0,8"
    [void]$panel.Children.Add($btnCheck)

    $list = New-Object System.Windows.Controls.ListBox
    $list.MinHeight = 140
    $list.Background  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $list.Foreground  = [System.Windows.Media.Brushes]::White
    $list.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
    [void]$panel.Children.Add($list)

    $hint = New-Object System.Windows.Controls.TextBlock
    Set-QOTControlTextSafe -Control $hint -Value "Add one or more mailbox addresses. Automatic email polling will be added later."
    $hint.Margin = "0,8,0,0"
    $hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    [void]$panel.Children.Add($hint)

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
        Set-EmailControlsEnabledState -Enabled $true -EmailBox $emailBox -BtnAdd $btnAdd -BtnRemove $btnRemove -BtnCheck $btnCheck -ListBox $list -HintText $hint
    })

    $chkEnable.Add_Unchecked({
        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.Enabled = $false
        Save-QOSettings -Settings $s
        Set-EmailControlsEnabledState -Enabled $false -EmailBox $emailBox -BtnAdd $btnAdd -BtnRemove $btnRemove -BtnCheck $btnCheck -ListBox $list -HintText $hint
    })

    $btnAdd.Add_Click({
        try {
            $addr = "$($emailBox.Text)".Trim()

            if ([string]::IsNullOrWhiteSpace($addr)) {
                 "Type an email address first."
                return
            }

            if ($addr -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                 "That email address format looks invalid."
                return
            }

            $s = Get-QOSettings

            # Defensive: always treat as array
            $current = @($s.Tickets.EmailIntegration.MonitoredAddresses) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
            if ($current -notcontains $addr) {
                $current += $addr
                $s.Tickets.EmailIntegration.MonitoredAddresses = @($current)
                Save-QOSettings -Settings $s
            }

            $emailBox.Text = ""
             "Saved."
            Refresh-MonitoredList -ListBox $list
        }
        catch {
             "Add failed. Check logs."
        }
    })

    $btnRemove.Add_Click({
        try {
            $sel = $list.SelectedItem
            if (-not $sel) {
                 "Select an address to remove."
                return
            }

            $remove = "$sel".Trim()

            $s = Get-QOSettings
            $current = @($s.Tickets.EmailIntegration.MonitoredAddresses) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
            $s.Tickets.EmailIntegration.MonitoredAddresses = @($current | Where-Object { $_ -ne $remove })

            Save-QOSettings -Settings $s

             "Removed."
            Refresh-MonitoredList -ListBox $list
        }
        catch {
             "Remove failed. Check logs."
        }
    })

    $btnCheck.Add_Click({
        try {
            if (Get-Command Invoke-QOEmailTicketPoll -ErrorAction SilentlyContinue) {
                $new = @(Invoke-QOEmailTicketPoll)

                if (Get-Command Update-QOTicketsGrid -ErrorAction SilentlyContinue) {
                    Update-QOTicketsGrid
                }

                if ($new.Count -gt 0) {
                     "Created $($new.Count) ticket(s) from email."
                } else {
                     "No new mail found."
                }
            }
            else {
                 "Tickets module not loaded, cannot poll email."
            }
        }
        catch {
             "Email poll failed. Check logs."
        }
    })

    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
