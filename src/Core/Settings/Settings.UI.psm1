# Settings.UI.psm1
# Settings UI for Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Import core settings (Get-QOSettings / Save-QOSettings)
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop

function Initialize-QOSettingsUI {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Guard: core settings must exist
    if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) {
        throw "Settings UI: Get-QOSettings not available. Core Settings.psm1 did not import."
    }

    # ------------------------------
    # Root + layout
    # ------------------------------
    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent
    $root.Padding    = "0"

    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "Auto" })) | Out-Null
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = "*" }))    | Out-Null

    # Title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text       = "Settings"
    $title.FontSize   = 18
    $title.FontWeight = "SemiBold"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.Margin     = "0,0,0,10"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    [void]$grid.Children.Add($title)

    # ------------------------------
    # Ticketing settings UI
    # ------------------------------
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = "0,0,0,0"
    [System.Windows.Controls.Grid]::SetRow($panel, 1)

    $ticketTitle = New-Object System.Windows.Controls.TextBlock
    $ticketTitle.Text       = "Ticketing"
    $ticketTitle.FontSize   = 14
    $ticketTitle.FontWeight = "SemiBold"
    $ticketTitle.Foreground = [System.Windows.Media.Brushes]::White
    $ticketTitle.Margin     = "0,0,0,8"
    [void]$panel.Children.Add($ticketTitle)

    $chkEnable = New-Object System.Windows.Controls.CheckBox
    $chkEnable.Content    = "Enable email to ticket creation"
    $chkEnable.Foreground = [System.Windows.Media.Brushes]::White
    $chkEnable.Margin     = "0,0,0,10"
    [void]$panel.Children.Add($chkEnable)

    $inputRow = New-Object System.Windows.Controls.StackPanel
    $inputRow.Orientation = "Horizontal"
    $inputRow.Margin      = "0,0,0,8"

    $emailBox = New-Object System.Windows.Controls.TextBox
    $emailBox.Width  = 320
    $emailBox.Margin = "0,0,8,0"
    $emailBox.Text   = ""
    [void]$inputRow.Children.Add($emailBox)

    $btnAdd = New-Object System.Windows.Controls.Button
    $btnAdd.Content = "Add"
    $btnAdd.Width   = 90
    [void]$inputRow.Children.Add($btnAdd)

    [void]$panel.Children.Add($inputRow)

    $list = New-Object System.Windows.Controls.ListBox
    $list.MinHeight = 140
    [void]$panel.Children.Add($list)

    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text       = "Add one or more mailbox addresses. Automatic email polling will be added later."
    $hint.Margin     = "0,8,0,0"
    $hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
    [void]$panel.Children.Add($hint)

    [void]$grid.Children.Add($panel)

    # ------------------------------
    # Helpers
    # ------------------------------
    function Ensure-TicketEmailDefaults {
        param($s)

        if (-not $s.Tickets) {
            $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        if (-not $s.Tickets.EmailIntegration) {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue (
                [pscustomobject]@{ Enabled = $false; MonitoredAddresses = @() }
            ) -Force
        }
        if ($null -eq $s.Tickets.EmailIntegration.MonitoredAddresses) {
            $s.Tickets.EmailIntegration.MonitoredAddresses = @()
        }

        return $s
    }

    function Refresh-MonitoredList {
        param($ListBox)

        $ListBox.Items.Clear()

        $s = Get-QOSettings
        $s = Ensure-TicketEmailDefaults $s

        foreach ($addr in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
            if ($addr) { [void]$ListBox.Items.Add($addr) }
        }
    }

    # Load settings into controls
    $settings = Get-QOSettings
    $settings = Ensure-TicketEmailDefaults $settings
    $chkEnable.IsChecked = [bool]$settings.Tickets.EmailIntegration.Enabled
    Refresh-MonitoredList -ListBox $list

    # ------------------------------
    # Events
    # ------------------------------
    $chkEnable.Add_Checked({
        $s = Ensure-TicketEmailDefaults (Get-QOSettings)
        $s.Tickets.EmailIntegration.Enabled = $true
        Save-QOSettings -Settings $s
        Refresh-MonitoredList -ListBox $list
    })

    $chkEnable.Add_Unchecked({
        $s = Ensure-TicketEmailDefaults (Get-QOSettings)
        $s.Tickets.EmailIntegration.Enabled = $false
        Save-QOSettings -Settings $s
        Refresh-MonitoredList -ListBox $list
    })

    $btnAdd.Add_Click({
        $email = $emailBox.Text.Trim()
        if (-not $email) { return }

        # basic sanity check
        if ($email -notmatch '.+@.+\..+') { return }

        $s = Ensure-TicketEmailDefaults (Get-QOSettings)

        if ($s.Tickets.EmailIntegration.MonitoredAddresses -notcontains $email) {
            $s.Tickets.EmailIntegration.MonitoredAddresses += $email
            Save-QOSettings -Settings $s
            Refresh-MonitoredList -ListBox $list
        }

        $emailBox.Text = ""
    })

    # Finish
    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
