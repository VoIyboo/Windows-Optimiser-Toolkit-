# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside MainWindow)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

# ------------------------------------------------------------
# Module state (handlers must rely on $script:)
# ------------------------------------------------------------
$script:QOSettingsState = @{
    Root      = $null
    TxtEmail  = $null
    BtnAdd    = $null
    BtnRemove = $null
    List      = $null
    Hint      = $null
    Addresses = $null
}

function Write-QOSettingsUILog {
    param([string]$Message)
    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $path = Join-Path $logDir "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    } catch { }
}

Write-QOSettingsUILog "=== Settings.UI.psm1 LOADED ==="

function Ensure-QOEmailIntegrationSettings {
    $s = Get-QOSettings
    if (-not $s) { $s = [pscustomobject]@{} }

    if (-not ($s.PSObject.Properties.Name -contains "Tickets") -or -not $s.Tickets) {
        $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($s.Tickets.PSObject.Properties.Name -contains "EmailIntegration") -or -not $s.Tickets.EmailIntegration) {
        $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if (-not ($s.Tickets.EmailIntegration.PSObject.Properties.Name -contains "MonitoredAddresses") -or $null -eq $s.Tickets.EmailIntegration.MonitoredAddresses) {
        $s.Tickets.EmailIntegration | Add-Member -NotePropertyName MonitoredAddresses -NotePropertyValue @() -Force
    }

    return $s
}

function Save-QOMonitoredAddresses {
    param(
        [Parameter(Mandatory)]
        [System.Collections.ObjectModel.ObservableCollection[string]] $Collection
    )

    $s = Ensure-QOEmailIntegrationSettings

    $clean = @(
        $Collection |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ }
    )

    $s.Tickets.EmailIntegration.MonitoredAddresses = $clean
    Save-QOSettings -Settings $s
}

function Find-QOElementByNameAndType {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [Type] $Type
    )

    function Walk {
        param($Parent)

        if ($null -eq $Parent) { return $null }

        try {
            if ($Parent -is $Type -and $Parent.Name -eq $Name) { return $Parent }
        } catch { }

        $count = 0
        try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent) }
        catch { return $null }

        for ($i = 0; $i -lt $count; $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
            $found = Walk $child
            if ($found) { return $found }
        }

        return $null
    }

    return (Walk $Root)
}

function Convert-SettingsWindowToHostableRoot {
    param(
        [Parameter(Mandatory)]
        [xml]$Doc
    )

    $win = $Doc.DocumentElement
    if (-not $win -or $win.LocalName -ne "Window") {
        throw "SettingsWindow.xaml root must be <Window>."
    }

    $ns   = $win.NamespaceURI
    $grid = $Doc.CreateElement("Grid", $ns)

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
            $newRes = $Doc.CreateElement("Grid.Resources", $ns)
            foreach ($rChild in @($child.ChildNodes)) {
                $null = $newRes.AppendChild($rChild.Clone())
            }
            $null = $grid.AppendChild($newRes)
        } else {
            $null = $grid.AppendChild($child.Clone())
        }
    }

    $null = $Doc.RemoveChild($win)
    $null = $Doc.AppendChild($grid)

    return $Doc
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

    Write-QOSettingsUILog "Loading SettingsWindow.xaml (hosted)"

    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $doc = Convert-SettingsWindowToHostableRoot -Doc $doc

    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root   = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load Settings view from SettingsWindow.xaml" }

    $txtEmail = Find-QOElementByNameAndType -Root $root -Name "TxtEmail"  -Type ([System.Windows.Controls.TextBox])
    $btnAdd   = Find-QOElementByNameAndType -Root $root -Name "BtnAdd"    -Type ([System.Windows.Controls.Button])
    $btnRem   = Find-QOElementByNameAndType -Root $root -Name "BtnRemove" -Type ([System.Windows.Controls.Button])
    $list     = Find-QOElementByNameAndType -Root $root -Name "LstEmails" -Type ([System.Windows.Controls.ListBox])
    $hint     = Find-QOElementByNameAndType -Root $root -Name "LblHint"   -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }

    Write-QOSettingsUILog ("TxtEmail type=" + $txtEmail.GetType().FullName)
    Write-QOSettingsUILog ("LstEmails type=" + $list.GetType().FullName)

    # Build addresses collection
    $addresses = New-Object 'System.Collections.ObjectModel.ObservableCollection[string]'
    $s = Ensure-QOEmailIntegrationSettings
    foreach ($e in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }

    # Bind
    $list.ItemsSource = $addresses

    # Store module state (handlers will read from here)
    $script:QOSettingsState.Root      = $root
    $script:QOSettingsState.TxtEmail  = $txtEmail
    $script:QOSettingsState.BtnAdd    = $btnAdd
    $script:QOSettingsState.BtnRemove = $btnRem
    $script:QOSettingsState.List      = $list
    $script:QOSettingsState.Hint      = $hint
    $script:QOSettingsState.Addresses = $addresses

    Write-QOSettingsUILog ("Bound list to collection. Count=" + $addresses.Count)

    # Wire handlers (no helper functions, no &, no scope weirdness)
    $btnAdd.Add_Click({
        try {
            $state = $script:QOSettingsState
            if (-not $state -or -not $state.Addresses) { throw "Addresses collection missing (module scope)" }

            $addr = ([string]$state.TxtEmail.Text).Trim()
            Write-QOSettingsUILog ("Add clicked. Input='" + $addr + "'")

            if (-not $addr) {
                if ($state.Hint) { $state.Hint.Text = "Enter an email address." }
                return
            }

            $lower = $addr.ToLower()
            foreach ($x in $state.Addresses) {
                if (([string]$x).Trim().ToLower() -eq $lower) {
                    $state.TxtEmail.Text = ""
                    if ($state.Hint) { $state.Hint.Text = "Already exists." }
                    Write-QOSettingsUILog "Add ignored (duplicate)"
                    return
                }
            }

            $state.Addresses.Add($addr)
            $state.TxtEmail.Text = ""

            Save-QOMonitoredAddresses -Collection $state.Addresses
            if ($state.Hint) { $state.Hint.Text = "Added $addr" }

            Write-QOSettingsUILog "Added + saved"
        }
        catch {
            $state = $script:QOSettingsState
            if ($state -and $state.Hint) { $state.Hint.Text = "Add failed. Check SettingsUI.log" }

            Write-QOSettingsUILog ("Add failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Add stack: " + $_.ScriptStackTrace)
        }
    })

    $btnRem.Add_Click({
        try {
            $state = $script:QOSettingsState
            if (-not $state -or -not $state.Addresses) { throw "Addresses collection missing (module scope)" }

            $sel = $state.List.SelectedItem
            Write-QOSettingsUILog ("Remove clicked. Selected='" + ($sel + "") + "'")

            if (-not $sel) {
                if ($state.Hint) { $state.Hint.Text = "Select an address to remove." }
                return
            }

            [void]$state.Addresses.Remove([string]$sel)

            Save-QOMonitoredAddresses -Collection $state.Addresses
            if ($state.Hint) { $state.Hint.Text = "Removed $sel" }

            Write-QOSettingsUILog "Removed + saved"
        }
        catch {
            $state = $script:QOSettingsState
            if ($state -and $state.Hint) { $state.Hint.Text = "Remove failed. Check SettingsUI.log" }

            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.ToString())
            Write-QOSettingsUILog ("Remove stack: " + $_.ScriptStackTrace)
        }
    })

    Write-QOSettingsUILog "Wired handlers (Add_Click)"
    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
