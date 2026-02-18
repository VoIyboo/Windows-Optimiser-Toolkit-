# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab (self-contained: finds controls from Window)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\\..\\Core\\Actions\\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "Apps.Helpers.psm1") -Force -ErrorAction Stop

function Find-QOTControlByName {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Root -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $direct = $Root.FindName($Name)
            if ($direct) { return $direct }
        }
    } catch { }

    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
    $q.Enqueue($Root) | Out-Null

    while ($q.Count -gt 0) {
        $cur = $q.Dequeue()
        if (-not $cur) { continue }

        $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
        if (-not $visited.Add($objId)) { continue }

        if ($cur -is [System.Windows.FrameworkElement]) {
            if ($cur.Name -eq $Name) { return $cur }
            try {
                $withinScope = $cur.FindName($Name)
                if ($withinScope) { return $withinScope }
            } catch { }
        } elseif ($cur -is [System.Windows.FrameworkContentElement]) {
            if ($cur.Name -eq $Name) { return $cur }
        }

        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                if ($child) { $q.Enqueue($child) | Out-Null }
            }
        } catch { }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur)
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            } catch { }
        }
    return $null
}

function Initialize-QOTAppsUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    try {
        # Ensure Apps data modules are available even when UI is loaded standalone
        Import-Module (Join-Path $PSScriptRoot "InstalledApps.psm1")     -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $PSScriptRoot "InstallCommonApps.psm1") -Force -ErrorAction SilentlyContinue
        # Find controls from XAML
        $AppsGrid        = Find-QOTControlByName -Root $Window -Name "AppsGrid"
        $InstallGrid     = Find-QOTControlByName -Root $Window -Name "InstallGrid"
        if (-not $AppsGrid)    { try { Write-QLog "Apps UI: Failed to resolve grid control AppsGrid (x:Name=AppsGrid)." "ERROR" } catch { }; return $false }
        if (-not $InstallGrid) { try { Write-QLog "Apps UI: Failed to resolve grid control InstallGrid (x:Name=InstallGrid)." "ERROR" } catch { }; return $false }

        Initialize-QOTAppsCollections

        $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
        $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

        try { Write-QLog ("Apps UI: Installed Apps ItemsSource bound ({0} rows currently)." -f @($Global:QOT_InstalledAppsCollection).Count) "DEBUG" } catch { }

        Initialize-QOTAppsGridsColumns -AppsGrid $AppsGrid -InstallGrid $InstallGrid

        # Load common apps catalogue (fast)
        Initialize-QOTCommonAppsCatalogue
        Write-QOTAppsCollectionDiagnostics -Label "Common App installs" -Items @($Global:QOT_CommonAppsCollection)

        # Auto scan installed apps on load (async)
        Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid

        Register-QOTActionGroup -Name "Apps" -GetItems ({
            param($Window)

            $items = @()
            $appsGrid = Find-QOTControlByName -Root $Window -Name "AppsGrid"
            $installGrid = Find-QOTControlByName -Root $Window -Name "InstallGrid"

            if ($appsGrid) {
                try { Commit-QOTGridEdits -Grid $appsGrid } catch { }
                foreach ($app in @($appsGrid.ItemsSource)) {
                    if (-not $app) { continue }
                    if ($app.PSObject.Properties.Name -notcontains "ActionId") {
                        $app | Add-Member -NotePropertyName ActionId -NotePropertyValue "Apps.Uninstall" -Force
                    }
                }
            }

            if ($installGrid) {
                try { Commit-QOTGridEdits -Grid $installGrid } catch { }
                foreach ($app in @($installGrid.ItemsSource)) {
                    if (-not $app) { continue }
                    if ($app.PSObject.Properties.Name -notcontains "ActionId") {
                        $app | Add-Member -NotePropertyName ActionId -NotePropertyValue "Apps.Install" -Force
                    }
                }
            }

            $appsGridRef = $appsGrid
            $installGridRef = $installGrid
            $items += [pscustomobject]@{
                ActionId = "Apps.RunSelected"
                Label = "Run selected app actions"
                IsSelected = ({
                    param($window)
                    $apps = if ($appsGridRef) { @($appsGridRef.ItemsSource) } else { @() }
                    $common = if ($installGridRef) { @($installGridRef.ItemsSource) } else { @() }
                    $installedSelected = @($apps | Where-Object { $_.IsSelected -eq $true })
                    $commonSelected = @($common | Where-Object { $_.IsSelected -eq $true -and $_.IsInstallable -ne $false })
                    return (($installedSelected.Count + $commonSelected.Count) -gt 0)
                }).GetNewClosure()
            }

            return $items
        }).GetNewClosure()

        try { Write-QLog "Apps tab UI initialised (Window based wiring)." "DEBUG" } catch { }
        return $true
    }
    catch {
        try { Write-QLog ("Apps UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
        return $false
    }
}

function Initialize-QOTAppsCollections {
    if (-not $Global:QOT_InstalledAppsCollection) {
        $Global:QOT_InstalledAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
    if (-not $Global:QOT_CommonAppsCollection) {
        $Global:QOT_CommonAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
}

function Initialize-QOTAppsGridsColumns {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$InstallGrid
    )

    # Installed Apps grid
    $AppsGrid.AutoGenerateColumns = $false
    $AppsGrid.CanUserAddRows      = $false
    $AppsGrid.IsReadOnly          = $false

    if ($AppsGrid.Columns.Count -eq 0) {
        $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridCheckBoxColumn -Property @{
            Header  = ""
            Binding = (New-Object System.Windows.Data.Binding "IsSelected")
            Width   = 40
            IsReadOnly = $false
        }))

        $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
            Header     = "Name"
            Binding    = (New-Object System.Windows.Data.Binding "Name")
            Width      = "*"
            IsReadOnly = $true
        }))

        $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
            Header     = "Publisher"
            Binding    = (New-Object System.Windows.Data.Binding "Publisher")
            Width      = 220
            IsReadOnly = $true
        }))
        $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
            Header     = "Version"
            Binding    = (New-Object System.Windows.Data.Binding "Version")
            Width      = 130
            IsReadOnly = $true
        }))

        $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
            Header     = "Source"
            Binding    = (New-Object System.Windows.Data.Binding "Source")
            Width      = 90
            IsReadOnly = $true
        }))

        $dateBinding = New-Object System.Windows.Data.Binding "InstallDate"
        $dateBinding.StringFormat = "yyyy-MM-dd"
        $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
            Header     = "Install Date"
            Binding    = $dateBinding
            Width      = 120
            IsReadOnly = $true
        }))
        
    }

    # Common Apps grid
    $InstallGrid.AutoGenerateColumns = $false
    $InstallGrid.CanUserAddRows      = $false
    $InstallGrid.IsReadOnly          = $false
    if ($InstallGrid.Columns.Count -eq 0) {
        $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridCheckBoxColumn -Property @{
            Header  = ""
            Binding = (New-Object System.Windows.Data.Binding "IsSelected")
            Width   = 34
            IsReadOnly = $false
        }))

        $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
            Header     = "App"
            Binding    = (New-Object System.Windows.Data.Binding "Name")
            Width      = "*"
            IsReadOnly = $true
        }))

        $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
            Header     = "Status"
            Binding    = (New-Object System.Windows.Data.Binding "Status")
            Width      = 120
            IsReadOnly = $true
        }))
    }
}

function Initialize-QOTCommonAppsCatalogue {

    $catalogue = $null
    $cmd = Get-Command Get-QOTCommonApps -ErrorAction SilentlyContinue
    if ($cmd) {
        $catalogue = @(Get-QOTCommonApps)
    } else {
        $catalogue = @(
            [pscustomobject]@{ IsSelected=$false; Name="Google Chrome"; WingetId="Google.Chrome"; Status="Unknown"; IsInstallable=$true }
            [pscustomobject]@{ IsSelected=$false; Name="7-Zip"; WingetId="7zip.7zip"; Status="Unknown"; IsInstallable=$true }
        )
    }

    $Global:QOT_CommonAppsCollection.Clear()
    foreach ($item in $catalogue) {
        if ($null -eq $item.PSObject.Properties["IsSelected"]) {
            $item | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
        }
        if ($null -eq $item.PSObject.Properties["ActionId"]) {
            $item | Add-Member -NotePropertyName ActionId -NotePropertyValue "Apps.Install" -Force
        }
        $Global:QOT_CommonAppsCollection.Add($item)
    }

    $commonCount = @($Global:QOT_CommonAppsCollection).Count
    try { Write-QLog ("Common App installs list populated: {0} rows" -f $commonCount) "INFO" } catch { }

    if ($commonCount -eq 0) {
        try { Write-QLog "Common App installs list is empty after catalogue load." "WARN" } catch { }
    }
}

Export-ModuleMember -Function Initialize-QOTAppsUI, Find-QOTControlByName
