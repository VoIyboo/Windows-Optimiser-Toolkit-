# Settings.UI.psm1
# Settings page UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop

# -------------------------------------------------------------------
# Script scope controls (prevents $null in event handlers)
# -------------------------------------------------------------------
$script:EmailBox  = $null
$script:BtnAdd    = $null
$script:BtnRemove = $null
$script:ListBox   = $null
$script:Hint      = $null

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
        if ($Control -is [System.Windows.Controls.TextBlock] -or
            $Control -is [System.Windows.Controls.TextBox]) {
            $Control.Text = $Value
            return
        }

        if ($Control -is [System.Windows.Controls.Label] -or
            $Control -is [System.Windows.Controls.ContentControl]) {
            $Control.Content = $Value
            return
        }

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

function Set-SettingsHint {
    param(
        [Parameter(Mandatory)] [string] $Message
    )
    Set-QOTControlTextSafe -Control $script:Hint -Value $Message
}

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
function Get-MonitoredAddresses {
    $s = Get-QOSettings

    $ma = $null
    if ($s -and $s.Tickets -and $s.Tickets.EmailIntegration) {
        $ma = $s.Tickets.EmailIntegration.MonitoredAddresses
    }

    if ($null -eq $ma) { return @() }

    if ($ma -is [string]) {
        $t = $ma.Trim()
        return @( if ($t) { $t } )
    }

    return @($ma) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
}

function Save-MonitoredAddresses {
    param(
        [Parameter(Mandatory)] [string[]] $Addresses
    )

    $s = Get-QOSettings

    if (-not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $clean = @($Addresses) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
    $s.Tickets.EmailIntegration.MonitoredAddresses = @($clean)

    Save-QOSettings -Settings $s
}

function Refresh-MonitoredList {
    $script:ListBox.Items.Clear()
    foreach ($addr in @(Get-MonitoredAddresses)) {
        [void]$script:ListBox.Items.Add($addr)
    }
}

function Remove-LastProcessedEntryIfPresent {
    param(
        [Parameter(Mandatory)] [string] $Mailbox
    )

    $s = Get-QOSettings
    if (-not ($s.Tickets -and $s.Tickets.EmailIntegration)) { return }

    if ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "LastProcessedByMailbox") {
        $lp = $s.Tickets.EmailIntegration.LastProcessedByMailbox
        if ($lp -and ($lp.PSObject.Properties.Name -contains $Mailbox)) {
            $lp.PSObject.Properties.Remove($Mailbox) | Out-Null
            Save-QOSettings -Settings $s
        }
    }
}

function Test-EmailFormat {
    param([Parameter(Mandatory)][string] $Email)
    return ($Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

# -------------------------------------------------------------------
# UI Builder
# -------------------------------------------------------------------
function Initialize-QOSettingsUI {
    param([Parameter(Mandatory)] $Window)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

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

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = "Horizontal"
    $row.Margin = "0,0,0,8"

    $script:EmailBox = New-Object System.Windows.Controls.TextBox
    $script:EmailBox.Width = 320
    $script:EmailBox.Margin = "0,0,8,0"
    $script:EmailBox.Background  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $script:EmailBox.Foreground  = [System.Windows.Media.Brushes]::White
    $script:EmailBox.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
    [void]$row.Children.Add($script:EmailBox)

    $script:BtnAdd = New-Object System.Windows.Controls.Button
    $script:BtnAdd.Content = "Add"
    $script:BtnAdd.Width = 90
    $script:BtnAdd.Margin = "0,0,8,0"
    [void]$row.Children.Add($script:BtnAdd)

    $script:BtnRemove = New-Object System.Windows.Controls.Button
    $script:BtnRemove.Content = "Remove"
    $script:BtnRemove.Width = 90
    [void]$row.Children.Add($script:BtnRemove)

    [void]$panel.Children.Add($row)

    $script:ListBox = New-Object System.Windows.Controls.ListBox
    $script:ListBox.MinHeight = 140
    $script:ListBox.Background  = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#020617")))
    $script:ListBox.Foreground  = [System.Windows.Media.Brushes]::White
    $script:ListBox.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#374151")))
    [void]$panel.Children.Add($script:ListBox)

    $script:Hint = New-Object System.Windows.Controls.TextBlock
    Set-QOTControlTextSafe -Control $script:Hint -Value "Add or remove mailbox addresses for email to ticket."
    $script:Hint.Margin = "0,8,0,0"
    $script:Hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    [void]$panel.Children.Add($script:Hint)

    Refresh-MonitoredList

    # -------------------------------------------------------------------
    # Add
    # -------------------------------------------------------------------
    $script:BtnAdd.Add_Click({
        try {
            $addr = "$($script:EmailBox.Text)".Trim()

            if ([string]::IsNullOrWhiteSpace($addr)) {
                Set-SettingsHint "Type an email address first."
                return
            }

            if (-not (Test-EmailFormat -Email $addr)) {
                Set-SettingsHint "That email address format looks invalid."
                return
            }

            $current = @(Get-MonitoredAddresses)

            if ($current -contains $addr) {
                Set-SettingsHint "Already in the list."
                return
            }

            $new = @($current + $addr)
            Save-MonitoredAddresses -Addresses $new

            $script:EmailBox.Text = ""
            Refresh-MonitoredList
            Set-SettingsHint "Added: $addr"
        }
        catch {
            Set-SettingsHint "Add failed. Check logs."
        }
    })

    # -------------------------------------------------------------------
    # Remove
    # -------------------------------------------------------------------
    $script:BtnRemove.Add_Click({
        try {
            $sel = $script:ListBox.SelectedItem
            if (-not $sel) {
                Set-SettingsHint "Select an address to remove."
                return
            }

            $remove = "$sel".Trim()
            $current = @(Get-MonitoredAddresses)

            $new = @($current | Where-Object { $_ -ne $remove })

            if ($new.Count -eq $current.Count) {
                Set-SettingsHint "Did not find that address in settings."
                return
            }

            Save-MonitoredAddresses -Addresses $new
            Remove-LastProcessedEntryIfPresent -Mailbox $remove

            Refresh-MonitoredList
            Set-SettingsHint "Removed: $remove"
        }
        catch {
            Set-SettingsHint "Remove failed. Check logs."
        }
    })

    $root.Child = $grid
    return $root
}

function New-QOTSettingsView {
    # Wrapper so MainWindow.UI.psm1 can request a settings panel easily
    return (Initialize-QOSettingsUI -Window $null)
}

Export-ModuleMember -Function Initialize-QOSettingsUI, New-QOTSettingsView
