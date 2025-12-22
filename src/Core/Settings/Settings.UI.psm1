# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside MainWindow)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

# ------------------------------------------------------------
# Module-scoped logger (handlers call this, not a function name)
# ------------------------------------------------------------
$script:QOLog = {
    param([string]$Message)
    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $path = Join-Path $logDir "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    } catch { }
}

& $script:QOLog "=== Settings.UI.psm1 LOADED ==="

# ------------------------------------------------------------
# One time WPF assembly load (prevents repeated Add-Type lag)
# ------------------------------------------------------------
$script:QOSettings_AssembliesLoaded = $false
function Initialize-QOSettingsUIAssemblies {
    if ($script:QOSettings_AssembliesLoaded) { return }
    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
        $script:QOSettings_AssembliesLoaded = $true
        & $script:QOLog "WPF assemblies loaded once"
    } catch {
        & $script:QOLog ("WPF assemblies load failed: " + $_.Exception.Message)
        throw
    }
}

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

function Get-QOControl {
    param(
        [Parameter(Mandatory)] $Root,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [Type] $Type
    )

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $c = $Root.FindName($Name)
            if ($c -and ($c -is $Type)) { return $c }
        }
    } catch { }

    return Find-QOElementByNameAndType -Root $Root -Name $Name -Type $Type
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

# ------------------------------------------------------------
# Handlers are stored module-wide so we can RemoveHandler cleanly
# ------------------------------------------------------------
$script:QOSettings_AddHandler = $null
$script:QOSettings_RemHandler = $null

function New-QOTSettingsView {
    param(
        [Parameter(Mandatory = $false)]
        $Window
    )

    Initialize-QOSettingsUIAssemblies

    $xamlPath = Join-Path $PSScriptRoot "SettingsWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "SettingsWindow.xaml not found at $xamlPath"
    }

    & $script:QOLog "Loading SettingsWindow.xaml (hosted)"

    [xml]$doc = Get-Content -LiteralPath $xamlPath -Raw
    $doc = Convert-SettingsWindowToHostableRoot -Doc $doc

    $reader = New-Object System.Xml.XmlNodeReader ($doc)
    $root   = [System.Windows.Markup.XamlReader]::Load($reader)
    if (-not $root) { throw "Failed to load Settings view from SettingsWindow.xaml" }

    $txtEmail = Get-QOControl -Root $root -Name "TxtEmail"  -Type ([System.Windows.Controls.TextBox])
    $btnAdd   = Get-QOControl -Root $root -Name "BtnAdd"    -Type ([System.Windows.Controls.Button])
    $btnRem   = Get-QOControl -Root $root -Name "BtnRemove" -Type ([System.Windows.Controls.Button])
    $list     = Get-QOControl -Root $root -Name "LstEmails" -Type ([System.Windows.Controls.ListBox])
    $hint     = Get-QOControl -Root $root -Name "LblHint"   -Type ([System.Windows.Controls.TextBlock])

    if (-not $txtEmail) { throw "TxtEmail not found (TextBox)" }
    if (-not $btnAdd)   { throw "BtnAdd not found (Button)" }
    if (-not $btnRem)   { throw "BtnRemove not found (Button)" }
    if (-not $list)     { throw "LstEmails not found (ListBox)" }

    & $script:QOLog ("TxtEmail type=" + $txtEmail.GetType().FullName)
    & $script:QOLog ("LstEmails type=" + $list.GetType().FullName)

    # Build addresses collection
    $addresses = New-Object 'System.Collections.ObjectModel.ObservableCollection[string]'
    $s = Ensure-QOEmailIntegrationSettings
    foreach ($e in @($s.Tickets.EmailIntegration.MonitoredAddresses)) {
        $v = ([string]$e).Trim()
        if ($v) { $addresses.Add($v) }
    }

    $list.ItemsSource = $addresses
    & $script:QOLog ("Bound list to collection. Count=" + $addresses.Count)

    # Remove old handlers to avoid double wiring (safe even if null)
    try {
        if ($script:QOSettings_AddHandler) {
            $btnAdd.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
        }
    } catch { }

    try {
        if ($script:QOSettings_RemHandler) {
            $btnRem.RemoveHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)
        }
    } catch { }

    # Handler: Add (closure captures controls + addresses)
    $script:QOSettings_AddHandler = [System.Windows.RoutedEventHandler]{
        try {
            $addr = ([string]$txtEmail.Text).Trim()
            & $script:QOLog ("Add clicked. Input='" + $addr + "'")

            if (-not $addr) {
                if ($hint) { $hint.Text = "Enter an email address." }
                return
            }

            $lower = $addr.ToLower()
            foreach ($x in $addresses) {
                if (([string]$x).Trim().ToLower() -eq $lower) {
                    $txtEmail.Text = ""
                    if ($hint) { $hint.Text = "Already exists." }
                    & $script:QOLog "Add ignored (duplicate)"
                    return
                }
            }

            $addresses.Add($addr)
            $txtEmail.Text = ""

            Save-QOMonitoredAddresses -Collection $addresses

            if ($hint) { $hint.Text = "Added $addr" }
            & $script:QOLog "Added + saved"
        }
        catch {
            & $script:QOLog ("Add failed: " + $_.Exception.ToString())
            & $script:QOLog ("Add stack: " + $_.ScriptStackTrace)
        }
    }.GetNewClosure()

    # Handler: Remove (closure captures controls + addresses)
    $script:QOSettings_RemHandler = [System.Windows.RoutedEventHandler]{
        try {
            $sel = $list.SelectedItem
            & $script:QOLog ("Remove clicked. Selected='" + ($sel + "") + "'")

            if (-not $sel) {
                if ($hint) { $hint.Text = "Select an address to remove." }
                return
            }

            [void]$addresses.Remove([string]$sel)
            Save-QOMonitoredAddresses -Collection $addresses

            if ($hint) { $hint.Text = "Removed $sel" }
            & $script:QOLog "Removed + saved"
        }
        catch {
            & $script:QOLog ("Remove failed: " + $_.Exception.ToString())
            & $script:QOLog ("Remove stack: " + $_.ScriptStackTrace)
        }
    }.GetNewClosure()

    # Wire using AddHandler (more reliable in PS than Add_Click)
    $btnAdd.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_AddHandler)
    $btnRem.AddHandler([System.Windows.Controls.Button]::ClickEvent, $script:QOSettings_RemHandler)

    & $script:QOLog "Wired handlers using AddHandler (closure-based, no this.Tag)"

    return $root
}

# Export only the view creator. Logging stays internal to avoid name conflicts.
Export-ModuleMember -Function New-QOTSettingsView
