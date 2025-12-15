# Settings.UI.psm1
# Settings page UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Tickets.psm1")  -Force -ErrorAction SilentlyContinue

function Ensure-QOTicketEmailDefaults {
    param([Parameter(Mandatory)] $Settings)

    if (-not ($Settings.PSObject.Properties.Name -contains "Tickets")) {
        $Settings | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($Settings.Tickets.PSObject.Properties.Name -contains "EmailIntegration")) {
        $Settings.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($Settings.Tickets.EmailIntegration.PSObject.Properties.Name -contains "Enabled")) {
        $Settings.Tickets.EmailIntegration | Add-Member -NotePropertyName Enabled -NotePropertyValue $false -Force
    }

    if (-not ($Settings.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses")) {
        $Settings.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    if ($null -eq $Settings.Tickets.EmailIntegration.MonitoredAddresses) {
        $Settings.Tickets.EmailIntegration.MonitoredAddresses = @()
    }
    elseif ($Settings.Tickets.EmailIntegration.MonitoredAddresses -is [string]) {
        $Settings.Tickets.EmailIntegration.MonitoredAddresses = @($Settings.Tickets.EmailIntegration.MonitoredAddresses)
    }
    else {
        $Settings.Tickets.EmailIntegration.MonitoredAddresses = @($Settings.Tickets.EmailIntegration.MonitoredAddresses)
    }

    return $Settings
}

function Refresh-MonitoredList {
    param([Parameter(Mandatory)] $ListBox)

    $ListBox.Items.Clear()

    $s = Ensure-QOTicketEmailDefaults (Get-QOSettings)
    foreach ($addr in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$addr)) {
            [void]$ListBox.Items.Add([string]$addr)
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

    $settings = Ensure-QOTicketEmailDefaults (Get-QOSettings)

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
    $hint.Text = "Add one or more mailbox addresses. Use Check email now to pull new mail into Tickets."
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
        $s = Ensure-QOTicketEmailDefaults (Get-QOSettings)
        $s.Tickets.EmailIntegration.Enabled = $true
        Save-QOSettings -Settings $s
        Set-EmailControlsEnabledState $true $emailBox $btnAdd $btnRemove $btnCheck $list $hint
    })

    $chkEnable.Add_Unchecked({
        $s = Ensure-QOTicketEmailDefaults (Get-QOSettings)
        $s.Tickets.EmailIntegration.Enabled = $false
        Save-QOSettings -Settings $s
        Set-EmailControlsEnabledState $false $emailBox $btnAdd $btnRemove $btnCheck $list $hint
    })

    $addAction = {
        $addr = $emailBox.Text
        if ($null -eq $addr) { $addr = "" }
        $addr = $addr.Trim()

        if ($addr -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return }

        $s = Ensure-QOTicketEmailDefaults (Get-QOSettings)

        $current = @($s.Tickets.EmailIntegration.MonitoredAddresses) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
        if ($current -notcontains $addr) {
            $s.Tickets.EmailIntegration.MonitoredAddresses = @($current + $addr)
            Save-QOSettings -Settings $s
        }

        $emailBox.Text = ""
        Refresh-MonitoredList -ListBox $list
    }

    $btnAdd.Add_Click($addAction)

    $emailBox.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            & $addAction
        }
    })

   $btnAdd.Add_Click({
    try {
        $addr = [string]$emailBox.Text
        if ($null -eq $addr) { $addr = "" }
        $addr = $addr.Trim()

        if ([string]::IsNullOrWhiteSpace($addr)) { return }
        if ($addr -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return }

        $s = Get-QOSettings

        # Ensure the whole tree exists
        if (-not $s.Tickets) {
            $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not $s.Tickets.EmailIntegration) {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses")) {
            $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
        }

        # Normalise to an array no matter what
        $s.Tickets.EmailIntegration.MonitoredAddresses = @($s.Tickets.EmailIntegration.MonitoredAddresses)

        if ($s.Tickets.EmailIntegration.MonitoredAddresses -notcontains $addr) {
            $s.Tickets.EmailIntegration.MonitoredAddresses += $addr
            Save-QOSettings -Settings $s
        }

        $emailBox.Text = ""
        Refresh-MonitoredList -ListBox $list
    }
    catch {
        Write-Host "Add address failed: $($_.Exception.Message)"
    }
})

Export-ModuleMember -Function Initialize-QOSettingsUI
