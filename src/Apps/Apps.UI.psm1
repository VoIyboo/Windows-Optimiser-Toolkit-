function Initialize-QOTAppsUI {
    param(
        [Parameter(Mandatory = $false)]
        [System.Windows.Controls.Button]$BtnScanApps,

        [Parameter(Mandatory = $false)]
        [System.Windows.Controls.Button]$BtnUninstallSelected,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$AppsGrid,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$InstallGrid,

        [Parameter(Mandatory = $false)]
        [System.Windows.Controls.Button]$RunButton
    )

    # These buttons are no longer part of the UX
    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    # Ensure global collections exist (ObservableCollection is best for WPF)
    if (-not $Global:QOT_InstalledAppsCollection) {
        $Global:QOT_InstalledAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
    if (-not $Global:QOT_CommonAppsCollection) {
        $Global:QOT_CommonAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }

    # Bind sources
    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    # Build columns explicitly (fast and stable, avoids AutoGenerate weirdness)
    Initialize-QOTAppsGridsColumns -AppsGrid $AppsGrid -InstallGrid $InstallGrid

    # Load common apps catalogue (fast, static list)
    Initialize-QOTCommonAppsCatalogue

    # Auto scan installed apps in the background (no UI freeze)
    Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid

    # Run selected actions does the actual work
    if ($RunButton) {
        $RunButton.Add_Click({
            Invoke-QOTUninstallSelectedApps -Grid $AppsGrid
            Invoke-QOTInstallSelectedCommonApps -Grid $InstallGrid
        })
    }

    Write-QLog "Apps tab UI initialised."
}

function Initialize-QOTAppsGridsColumns {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$InstallGrid
    )

    # Installed Apps grid
    $AppsGrid.AutoGenerateColumns = $false
    $AppsGrid.Columns.Clear()

    $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridCheckBoxColumn -Property @{
        Header  = ""
        Binding = (New-Object System.Windows.Data.Binding "IsSelected")
        Width   = 40
    }))

    $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header  = "Name"
        Binding = (New-Object System.Windows.Data.Binding "Name")
        Width   = "*"
        IsReadOnly = $true
    }))

    $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header  = "Version"
        Binding = (New-Object System.Windows.Data.Binding "Version")
        Width   = 140
        IsReadOnly = $true
    }))

    $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header  = "Publisher"
        Binding = (New-Object System.Windows.Data.Binding "Publisher")
        Width   = 200
        IsReadOnly = $true
    }))

    # Common Apps grid (catalogue)
    $InstallGrid.AutoGenerateColumns = $false
    $InstallGrid.Columns.Clear()

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridCheckBoxColumn -Property @{
        Header  = ""
        Binding = (New-Object System.Windows.Data.Binding "IsSelected")
        Width   = 40
    }))

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header  = "App"
        Binding = (New-Object System.Windows.Data.Binding "Name")
        Width   = "*"
        IsReadOnly = $true
    }))

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header  = "Version"
        Binding = (New-Object System.Windows.Data.Binding "Version")
        Width   = 140
        IsReadOnly = $true
    }))
}
