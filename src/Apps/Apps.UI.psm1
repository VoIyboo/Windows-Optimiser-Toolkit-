# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab (self-contained: finds controls from Window)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\\..\\Core\\Actions\\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "Apps.Helpers.psm1") -Force -ErrorAction Stop

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
        $AppsGrid        = $Window.FindName("AppsGrid")
        $InstallGrid     = $Window.FindName("InstallGrid")
        $StatusLabel     = $Window.FindName("StatusLabel")

        if (-not $AppsGrid)    { try { Write-QLog "Apps UI: AppsGrid not found in XAML (x:Name='AppsGrid')." "ERROR" } catch { }; return $false }
        if (-not $InstallGrid) { try { Write-QLog "Apps UI: InstallGrid not found in XAML (x:Name='InstallGrid')." "ERROR" } catch { }; return $false }

        Initialize-QOTAppsCollections

        $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
        $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

        Initialize-QOTAppsGridsColumns -AppsGrid $AppsGrid -InstallGrid $InstallGrid

        # Load common apps catalogue (fast)
        Initialize-QOTCommonAppsCatalogue

        # Auto scan installed apps on load (async)
        Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid

        Register-QOTActionGroup -Name "Apps" -GetItems ({
            param($Window)

            $items = @()
            $appsGrid = $Window.FindName("AppsGrid")
            $installGrid = $Window.FindName("InstallGrid")

            if ($appsGrid) { try { Commit-QOTGridEdits -Grid $appsGrid } catch { } }
            if ($installGrid) { try { Commit-QOTGridEdits -Grid $installGrid } catch { } }

            if ($appsGrid -or $installGrid) {
                $appsGridRef = $appsGrid
                $installGridRef = $installGrid
                $statusLabelRef = $Window.FindName("StatusLabel")
                $items += [pscustomobject]@{
                    ActionId = "Apps.RunSelected"
                    Label = "Run selected app actions"
                    IsSelected = ({
                        param($window)
                        $apps = @($appsGridRef.ItemsSource)
                        $common = @($installGridRef.ItemsSource)
                        $installedSelected = @($apps | Where-Object { $_.IsSelected -eq $true })
                        $commonSelected = @($common | Where-Object { $_.IsSelected -eq $true -and $_.IsInstallable -ne $false })
                        return (($installedSelected.Count + $commonSelected.Count) -gt 0)
                    }).GetNewClosure()
                }
            }

            return $items
        }).GetNewClosure()

        try { Write-QLog "Apps tab UI initialised (Window based wiring)." "DEBUG" } catch { }
        return $true
    }
    catch {
        try { Write-QLog ("Apps UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
        return $true
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
        $Global:QOT_CommonAppsCollection.Add($item)
    }

    try { Write-QLog ("Common apps catalogue loaded ({0} items)." -f $Global:QOT_CommonAppsCollection.Count) "DEBUG" } catch { }
}

Export-ModuleMember -Function Initialize-QOTAppsUI
