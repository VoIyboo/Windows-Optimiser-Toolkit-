# SettingsWindow.UI.psm1

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\..\Core\Settings.psm1") -Force

function Show-QOTSettingsWindow {
    param(
        [Parameter(Mandatory)]
        $Owner
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "SettingsWindow.xaml"
    $xaml = Get-Content $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)

    $win.Owner = $Owner

    $txtEmail = $win.FindName("TxtEmail")
    $btnAdd   = $win.FindName("BtnAdd")
    $btnRem   = $win.FindName("BtnRemove")
    $list     = $win.FindName("LstEmails")
    $hint     = $win.FindName("LblHint")

    function Refresh-List {
        $list.Items.Clear()
        $s = Get-QOSettings
        $emails = @($s.Tickets.EmailIntegration.MonitoredAddresses)
        foreach ($e in $emails) {
            [void]$list.Items.Add($e)
        }
    }

    Refresh-List

    $btnAdd.Add_Click({
        try {
            $addr = $txtEmail.Text.Trim()
            if (-not $addr) { $hint.Text = "Enter an email address."; return }

            $s = Get-QOSettings
            if (-not $s.Tickets) { $s | Add-Member Tickets ([pscustomobject]@{}) -Force }
            if (-not $s.Tickets.EmailIntegration) {
                $s.Tickets | Add-Member EmailIntegration ([pscustomobject]@{}) -Force
            }

            $current = @($s.Tickets.EmailIntegration.MonitoredAddresses)
            if ($current -contains $addr) {
                $hint.Text = "Already exists."
                return
            }

            $s.Tickets.EmailIntegration.MonitoredAddresses = @($current + $addr)
            Save-QOSettings -Settings $s

            $txtEmail.Text = ""
            $hint.Text = "Added $addr"
            Refresh-List
        }
        catch {
            $hint.Text = "Add failed. Check logs."
        }
    })

    $btnRem.Add_Click({
        $sel = $list.SelectedItem
        if (-not $sel) { $hint.Text = "Select an address."; return }

        $s = Get-QOSettings
        $s.Tickets.EmailIntegration.MonitoredAddresses =
            @($s.Tickets.EmailIntegration.MonitoredAddresses | Where-Object { $_ -ne $sel })

        Save-QOSettings -Settings $s
        $hint.Text = "Removed $sel"
        Refresh-List
    })

    $win.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Show-QOTSettingsWindow
