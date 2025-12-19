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

    # Allow the XAML to be simple. These buttons can be removed entirely.
    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    # Make sure something shows even if XAML columns do not match property names
    try {
        if ($AppsGrid.Columns.Count -eq 0) { $AppsGrid.AutoGenerateColumns = $true }
        if ($InstallGrid.Columns.Count -eq 0) { $InstallGrid.AutoGenerateColumns = $true }
    } catch { }

    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    if ($RunButton) {
        $RunButton.Add_Click({
            Invoke-QOTUninstallSelectedApps -Grid $AppsGrid
            Invoke-QOTInstallSelectedCommonApps -Grid $InstallGrid
        })
    }

    # Auto scan on load, no button required
    Refresh-QOTInstalledAppsGrid -Grid $AppsGrid
    Refresh-QOTCommonAppsGrid    -Grid $InstallGrid

    Write-QLog "Apps tab UI initialised."
}
