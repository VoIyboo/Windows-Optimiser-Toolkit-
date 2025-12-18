# src\Core\Settings\Settings.UI.psm1
# Settings UI (hosted inside MainWindow)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\Settings.psm1") -Force -ErrorAction Stop

function Write-QOSettingsUILog {
    param([string]$Message)

    try {
        $logDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $path = Join-Path $logDir "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
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

function Save-QOMonitoredAddresses {
    param(
        [Parameter(Mandatory)]
        [System.Collections.ObjectModel.ObservableCollection[string]] $Collection
    )

    $s = Ensure-QOEmailIntegrationSettings
    $s.Tickets.EmailIntegration.MonitoredAddresses = @($Collection | Where-Object { $_ -and $_.Trim() } )
    Save-QOSettings -Settings $s
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

    function Find-QOElementByName {
        param(
            [Parameter(Mandatory)] $Root,
            [Parameter(Mandatory)] [string] $Name
        )
    
        # 1) Try FrameworkElement.FindName first (best for namescopes)
        try {
            if ($Root -is [System.Windows.FrameworkElement]) {
                $r = $Root.FindName($Name)
                if ($r) { return $r }
            }
        } catch { }
    
        # 2) Fallback: Visual tree walk
        function Walk {
            param($Parent)
    
            if ($null -eq $Parent) { return $null }
    
            try {
                if ($Parent -is [System.Windows.FrameworkElement] -and $Parent.Name -eq $Name) {
                    return $Parent
                }
            } catch { }
    
            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent) } catch { return $null }
    
            for ($i = 0; $i -lt $count; $i++) {
                $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
                $found = Walk $child
                if ($found) { return $found }
            }
    
            return $null
        }
    
        return (Walk $Root)
    }


    # Bind list to collection (this fixes the "Items.Add does nothing" problem)
    $list.ItemsSource = $addresses

    Write-QOSettingsUILog ("Bound list to collection. Count=" + $addresses.Count)

    $btnAdd.Add_Click({
        try {
            $addr = ($txtEmail.Text + "").Trim()
            Write-QOSettingsUILog ("Add clicked. Input='" + $addr + "'")

            if (-not $addr) { return }

            # Case-insensitive duplicate check
            $exists = $false
            foreach ($x in $addresses) {
                if (($x + "").Trim().ToLower() -eq $addr.ToLower()) { $exists = $true; break }
            }

            if (-not $exists) {
                $addresses.Add($addr)   # UI updates instantly
                Write-QOSettingsUILog "Added to collection"
            }
            else {
                Write-QOSettingsUILog "Already existed"
            }

            $txtEmail.Text = ""
            Save-QOMonitoredAddresses -Collection $addresses
            Write-QOSettingsUILog "Saved settings"
        }
        catch {
            Write-QOSettingsUILog ("Add failed: " + $_.Exception.Message)
        }
    })

    $btnRem.Add_Click({
        try {
            $sel = $list.SelectedItem
            Write-QOSettingsUILog ("Remove clicked. Selected='" + ($sel + "") + "'")

            if (-not $sel) { return }

            [void]$addresses.Remove([string]$sel)  # UI updates instantly
            Save-QOMonitoredAddresses -Collection $addresses
            Write-QOSettingsUILog "Removed and saved"
        }
        catch {
            Write-QOSettingsUILog ("Remove failed: " + $_.Exception.Message)
        }
    })

    return $root
}

Export-ModuleMember -Function New-QOTSettingsView
