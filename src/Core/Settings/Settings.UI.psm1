# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside the main window, no popups for normal use)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

function Write-QOSettingsUILog {
    param([string]$Message)

    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null

        $path = Join-Path $logDir "SettingsUI.log"
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    }
    catch { }
}

function Set-QOHintText {
    param(
        $HintControl,
        [AllowEmptyString()]
        [string] $Text
    )

    try {
        if ($null -eq $HintControl) { return }

        if ($HintControl.PSObject.Properties.Match("Text").Count -gt 0) {
            $HintControl.Text = $Text
            return
        }

        if ($HintControl.PSObject.Properties.Match("Content").Count -gt 0) {
            $HintControl.Content = $Text
            return
        }
    }
    catch { }
}

function Ensure-QOEmailIntegrationSettings {
    $s = Get-QOSettings
    if (-not $s) { $s = [pscustomobject]@{} }

    if (-not ($s.PSObject.Properties.Name -contains "Tickets")) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not ($s.Tickets.PSObject.Properties.Name -contains "EmailIntegration")) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses")) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    return $s
}

function Refresh-QOEmailList {
    param(
        [Parameter(Mandatory)] $ListControl
    )

    $ListControl.Items.Clear()

    $s = Ensure-QOEmailIntegrationSettings
    foreach ($e in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
        [void]$ListControl.Items.Add([string]$e)
    }
}

function New-QOTSettingsView {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "SettingsWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "SettingsWindow.xaml not found at $xamlPath"
    }

    Write-QOSettingsUILog "Loading SettingsWindow.xaml"

    # Convert root <Window> to <Grid> so it can be hosted
    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw

    $win = $doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") {
        throw "SettingsWindow.xaml root must be <Window>."
    }

    $ns   = $win.NamespaceURI
    $grid = $doc.CreateElement("Grid", $ns)

    $removeAttrs = @(
        "Title","Height","Width","Topmost","WindowStartupLocation",
        "ResizeMode","SizeToContent","ShowInTaskbar","WindowStyle","AllowsTransparency"
    )

    foreach ($a in @($win.Attributes)) {
        if ($removeAttrs -contains $a.Name) { continue }
        $null = $grid.Attributes.Append($a.Clone())
    }

    foreach ($child in @($win.ChildNodes)) {
        if ($child.NodeType -ne "Element") { continue }

        if ($child.LocalName -eq "Window.Resources") {
            $newRes = $doc.CreateElement("Grid.Resources", $ns)
            foreach ($rChild in @($child.ChildNodes)) {
                $null = $newRes.AppendChild($rChild.Clone())
            }
            $null = $grid.AppendChild($newRes)
        }
        else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $doc.RemoveChild($win)
    $null = $doc.AppendChild($grid)

    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root   = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load Settings view from SettingsWindow.xaml" }

    function Find-QONode {
        param([Parameter(Mandatory)] $Root, [Parameter(Mandatory)] [string] $Name)
        [System.Windows.LogicalTreeHelper]::FindLogicalNode($Root, $Name)
    }

    $txtEmail = Find-QONode -Root $root -Name "TxtEmail"
    $btnAdd   = Find-QONode -Root $root -Name "BtnAdd"
    $btnRem   = Find-QONode -Root $root -Name "BtnRemove"
    $list     = Find-QONode -Root $root -Name "LstEmails"
    $hint     = Find-QONode -Root $root -Name "LblHint"

    if (-not $txtEmail) { throw "TxtEmail not found" }
    if (-not $btnAdd)   { throw "BtnAdd not found" }
    if (-not $btnRem)   { throw "BtnRemove not found" }
    if (-not $list)     { throw "LstEmails not found" }

    Refresh-QOEmailList -ListControl $list
    Set-QOHintText -HintControl $hint -Text ""

    Write-QOSettingsUILog "Settings UI loaded. Wiring events."

    $btnAdd.Add_Click({
        Write-QOSettingsUILog "Add clicked"

        try {
            $addr = ($txtEmail.Text + "").Trim()
            Write-QOSettingsUILog ("Add input: '" + $addr + "'")

            if (-not $addr) {
                Set-QOHintText -HintControl $hint -Text "Enter an email address."
                return
            }

            $s = Ensure-QOEmailIntegrationSettings
            $current = @($s.Tickets.EmailIntegration.MonitoredAddresses)

            if ($current -contains $addr) {
                Set-QOHintText -HintControl $hint -Text "Already exists."
                return
            }

            $s.Tickets.EmailIntegration.MonitoredAddresses = @($current + $addr)
            Save-QOSettings -Settings $s

            $txtEmail.Text = ""
            Refresh-QOEmailList -ListControl $list
            Set-QOHintText -HintControl $hint -Text "Added $addr"

            Write-QOSettingsUILog "Add succeeded"
        }
        catch {
            $msg = "Add failed: " + $_.Exception.Message
            Write-QOSettingsUILog $msg
            Set-QOHintText -HintControl $hint -Text $msg

            try { [System.Windows.MessageBox]::Show($msg, "Settings") | Out-Null } catch { }
        }
    })

    $btnRem.Add_Click({
        Write-QOSettingsUILog "Remove clicked"

        try {
            $sel = $list.SelectedItem
            Write-QOSettingsUILog ("Remove selected: '" + ($sel + "") + "'")

            if (-not $sel) {
                Set-QOHintText -HintControl $hint -Text "Select an address."
                return
            }

            $s = Ensure-QOEmailIntegrationSettings
            $s.Tickets.EmailIntegration.MonitoredAddresses =
                @($s.Tickets.EmailIntegration.MonitoredAddresses | Where-Object { $_ -ne $sel })

            Save-QOSettings -Settings $s

            Refresh-QOEmailList -ListControl $list
            Set-QOHintText -HintControl $hint -Text "Removed $sel"

            Write-QOSettingsUILog "Remove succeeded"
        }
        catch {
            $msg = "Remove failed: " + $_.Exception.Message
            Write-QOSettingsUILog $msg
            Set-QOHintText -HintControl $hint -Text $msg

            try { [System.Windows.MessageBox]::Show($msg, "Settings") | Out-Null } catch { }
        }
    })

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
