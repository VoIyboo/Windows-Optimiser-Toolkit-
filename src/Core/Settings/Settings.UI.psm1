Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Settings.psm1") -Force -ErrorAction Stop


$ErrorActionPreference = "Stop"

function Initialize-QOSettingsUI {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $root = New-Object System.Windows.Controls.Border
    $root.Background = [System.Windows.Media.Brushes]::Transparent
    $root.Padding = "0"

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

    return $root
}
# ------------------------------
# Ticketing settings UI
# ------------------------------
if (-not (Get-Command Get-QOSettings -ErrorAction SilentlyContinue)) {
    throw "Settings UI: Get-QOSettings not available. Core Settings.psm1 did not import."
}

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


$panel = New-Object System.Windows.Controls.StackPanel
$panel.Margin = "0,0,0,0"
[System.Windows.Controls.Grid]::SetRow($panel, 1)

$ticketTitle = New-Object System.Windows.Controls.TextBlock
$ticketTitle.Text = "Ticketing"
$ticketTitle.FontSize = 14
$ticketTitle.FontWeight = "SemiBold"
$ticketTitle.Foreground = [System.Windows.Media.Brushes]::White
$ticketTitle.Margin = "0,0,0,8"
$panel.Children.Add($ticketTitle) | Out-Null

$chkEnable = New-Object System.Windows.Controls.CheckBox
$chkEnable.Content = "Enable email to ticket creation"
$chkEnable.IsChecked = $settings.Tickets.EmailIntegration.Enabled
$chkEnable.Foreground = [System.Windows.Media.Brushes]::White
$chkEnable.Margin = "0,0,0,10"
$panel.Children.Add($chkEnable) | Out-Null

$inputRow = New-Object System.Windows.Controls.StackPanel
$inputRow.Orientation = "Horizontal"
$inputRow.Margin = "0,0,0,8"

$emailBox = New-Object System.Windows.Controls.TextBox
$emailBox.Width = 320
$emailBox.Margin = "0,0,8,0"
$emailBox.Text = ""
$inputRow.Children.Add($emailBox) | Out-Null

$btnAdd = New-Object System.Windows.Controls.Button
$btnAdd.Content = "Add"
$btnAdd.Width = 90
$inputRow.Children.Add($btnAdd) | Out-Null

$panel.Children.Add($inputRow) | Out-Null

$list = New-Object System.Windows.Controls.ListBox
$list.MinHeight = 140
$panel.Children.Add($list) | Out-Null

$hint = New-Object System.Windows.Controls.TextBlock
$hint.Text = "Add one or more mailbox addresses. Automatic email polling will be added later."
$hint.Margin = "0,8,0,0"
$hint.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#9CA3AF")))
$panel.Children.Add($hint) | Out-Null

$grid.Children.Add($panel) | Out-Null

# ------------------------------
# Events and persistence
# ------------------------------
$chkEnable.Add_Checked({
    $s = Get-QOSettings
    $s.Tickets.EmailIntegration.Enabled = $true
    Save-QOSettings -Settings $s
})

$chkEnable.Add_Unchecked({
    $s = Get-QOSettings
    $s.Tickets.EmailIntegration.Enabled = $false
    Save-QOSettings -Settings $s
})

$btnAdd.Add_Click({
    $email = $emailBox.Text.Trim()
    if (-not $email) { return }

    # basic sanity check
    if ($email -notmatch '.+@.+\..+') { return }

    $s = Get-QOSettings

    if ($s.Tickets.EmailIntegration.MonitoredAddresses -notcontains $email) {
        $s.Tickets.EmailIntegration.MonitoredAddresses += $email
        Save-QOSettings -Settings $s
        $list.ItemsSource = $null
        $list.ItemsSource = @($s.Tickets.EmailIntegration.MonitoredAddresses)

    }

    $emailBox.Text = ""
})


    $root.Child = $grid
    return $root
}

Export-ModuleMember -Function Initialize-QOSettingsUI
