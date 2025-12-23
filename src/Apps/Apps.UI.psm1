# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab

$ErrorActionPreference = "Stop"

# Keep worker alive so async scan reliably completes
$script:QOT_InstalledAppsWorker = $null
$script:QOT_InstalledAppsScanStarted = $false

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

    # Hide legacy buttons (keep XAML as-is for now)
    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    Initialize-QOTAppsCollections

    # Bind sources
    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    # IMPORTANT:
    # Your XAML sets IsReadOnly="True" on AppsGrid and InstallGrid.
    # That makes checkboxes painful and can prevent clean commits.
    # We only want the text columns read-only, not the whole grid.
    try { $AppsGrid.IsReadOnly    = $false } catch { }
    try { $InstallGrid.IsReadOnly = $false } catch { }

    # Build the common apps list instantly (no slow scanning)
    Refresh-QOTCommonAppsGrid -Grid $InstallGrid

    # Wire Run button (uninstall + installs use this)
    if ($RunButton) {
        $RunButton.Add_Click({
            try { Commit-QOTGridEdits -Grid $AppsGrid } catch { }
            try { Commit-QOTGridEdits -Grid $InstallGrid } catch { }

            try { Invoke-QOTUninstallSelectedApps -Grid $AppsGrid } catch { try { Write-QLog ("Uninstall failed: {0}" -f $_.Exception.Message) "ERROR" } catch { } }
            try { Invoke-QOTInstallSelectedCommonApps -Grid $InstallGrid } catch { try { Write-QLog ("Install failed: {0}" -f $_.Exception.Message) "ERROR" } catch { } }
        })
    }

    # Auto scan installed apps AFTER UI paints (prevents “empty grid forever” issues)
    Start-QOTInstalledAppsScanAfterRender -AppsGrid $AppsGrid

    try { Write-QLog "Apps tab UI initialised." } catch { }
}

function Initialize-QOTAppsCollections {
    if (-not $Global:QOT_InstalledAppsCollection) {
        $Global:QOT_InstalledAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
    if (-not $Global:QOT_CommonAppsCollection) {
        $Global:QOT_CommonAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
}

function Commit-QOTGridEdits {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    try {
        $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
        $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true) | Out-Null
    } catch { }
}

function Start-QOTInstalledAppsScanAfterRender {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$AppsGrid
    )

    if ($script:QOT_InstalledAppsScanStarted) { return }
    $script:QOT_InstalledAppsScanStarted = $true

    try {
        $dispatcher = $AppsGrid.Dispatcher

        # Queue scan on UI thread once the control is rendered and ready
        $dispatcher.BeginInvoke([action]{
            Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid
        }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    }
    catch {
        try { Write-QLog ("Start-QOTInstalledAppsScanAfterRender failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

function Start-QOTInstalledAppsScanAsync {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$AppsGrid
    )

    try {
        if (-not (Get-Command Get-QOTInstalledApps -ErrorAction SilentlyContinue)) {
            try { Write-QLog "Get-QOTInstalledApps not found. Check Apps\InstalledApps.psm1 imported successfully." "ERROR" } catch { }
            return
        }

        $dispatcher = $AppsGrid.Dispatcher

        $script:QOT_InstalledAppsWorker = New-Object System.ComponentModel.BackgroundWorker
        $script:QOT_InstalledAppsWorker.WorkerReportsProgress = $false
        $script:QOT_InstalledAppsWorker.WorkerSupportsCancellation = $false

        $script:QOT_InstalledAppsWorker.DoWork += {
            param($sender, $e)
            try { Write-QLog "Installed apps scan started." "DEBUG" } catch { }
            $e.Result = @(Get-QOTInstalledApps)
        }

        $script:QOT_InstalledAppsWorker.RunWorkerCompleted += {
            param($sender, $e)

            if ($e.Error) {
                try { Write-QLog ("Installed apps scan failed: {0}" -f $e.Error.Message) "ERROR" } catch { }
                return
            }

            $results = @($e.Result)

            $dispatcher.Invoke([action]{
                try {
                    $Global:QOT_InstalledAppsCollection.Clear()

                    foreach ($app in $results) {
                        Ensure-QOTInstalledAppForGrid -App $app
                        $Global:QOT_InstalledAppsCollection.Add($app)
                    }

                    # Force a refresh in case WPF didn’t repaint from collection changes
                    $AppsGrid.ItemsSource = $null
                    $AppsGrid.ItemsSource = $Global:QOT_InstalledAppsCollection
                    $AppsGrid.Items.Refresh()
                }
                catch {
                    try { Write-QLog ("Failed to populate installed apps grid: {0}" -f $_.Exception.Message) "ERROR" } catch { }
                }
            })

            try { Write-QLog ("Installed apps loaded: {0}" -f $results.Count) "INFO" } catch { }
        }

        $script:QOT_InstalledAppsWorker.RunWorkerAsync() | Out-Null
    }
    catch {
        try { Write-QLog ("Start-QOTInstalledAppsScanAsync error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

function Ensure-QOTInstalledAppForGrid {
    param(
        [Parameter(Mandatory)]
        [object]$App
    )

    if ($null -eq $App.PSObject.Properties["IsSelected"]) {
        $App | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
    }
    if ($null -eq $App.PSObject.Properties["Name"]) {
        $App | Add-Member -NotePropertyName Name -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["Publisher"]) {
        $App | Add-Member -NotePropertyName Publisher -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["UninstallString"]) {
        $App | Add-Member -NotePropertyName UninstallString -NotePropertyValue "" -Force
    }
}

function Refresh-QOTCommonAppsGrid {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    try {
        $Global:QOT_CommonAppsCollection.Clear()

        # Use InstallCommonApps.psm1 if available
        if (Get-Command Get-QOTCommonApps -ErrorAction SilentlyContinue) {
            $items = @(Get-QOTCommonApps)
        }
        else {
            $items = @(
                [pscustomobject]@{ IsSelected=$false; Name="Google Chrome";      WingetId="Google.Chrome";              Status="Available"; IsInstallable=$true }
                [pscustomobject]@{ IsSelected=$false; Name="Microsoft Edge";     WingetId="Microsoft.Edge";             Status="Available"; IsInstallable=$true }
                [pscustomobject]@{ IsSelected=$false; Name="7-Zip";              WingetId="7zip.7zip";                  Status="Available"; IsInstallable=$true }
                [pscustomobject]@{ IsSelected=$false; Name="Notepad++";          WingetId="Notepad++.Notepad++";        Status="Available"; IsInstallable=$true }
            )
        }

        foreach ($i in $items) {
            if ($null -eq $i.PSObject.Properties["IsSelected"])    { $i | Add-Member -NotePropertyName IsSelected    -NotePropertyValue $false -Force }
            if ($null -eq $i.PSObject.Properties["IsInstallable"]) { $i | Add-Member -NotePropertyName IsInstallable -NotePropertyValue $true  -Force }
            if ($null -eq $i.PSObject.Properties["Status"])        { $i | Add-Member -NotePropertyName Status        -NotePropertyValue "Available" -Force }
            $Global:QOT_CommonAppsCollection.Add($i)
        }

        $Grid.Items.Refresh()
        try { Write-QLog ("Common apps loaded: {0}" -f $Global:QOT_CommonAppsCollection.Count) "INFO" } catch { }
    }
    catch {
        try { Write-QLog ("Refresh-QOTCommonAppsGrid failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    try { Commit-QOTGridEdits -Grid $Grid } catch { }

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true -and -not [string]::IsNullOrWhiteSpace($_.WingetId) })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps selected." "INFO" } catch { }
        return
    }

    foreach ($app in $selected) {
        try {
            if (-not (Get-Command Install-QOTCommonApp -ErrorAction SilentlyContinue)) {
                throw "Install-QOTCommonApp not found. Check Apps\InstallCommonApps.psm1 imported."
            }

            Install-QOTCommonApp -Name $app.Name -WingetId $app.WingetId
            $app.IsSelected = $false
        }
        catch {
            try { Write-QLog ("Install failed for '{0}': {1}" -f $app.Name, $_.Exception.Message) "ERROR" } catch { }
        }
    }
}

function Invoke-QOTUninstallSelectedApps {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    try { Commit-QOTGridEdits -Grid $Grid } catch { }

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Uninstall skipped. No installed apps selected." "INFO" } catch { }
        return
    }

    foreach ($app in $selected) {
        $name = $app.Name
        $cmd  = $app.UninstallString

        if ([string]::IsNullOrWhiteSpace($cmd)) {
            try { Write-QLog ("Skipping uninstall for '{0}' because UninstallString is empty." -f $name) "WARN" } catch { }
            continue
        }

        try {
            try { Write-QLog ("Uninstalling: {0}" -f $name) "INFO" } catch { }
            Start-QOTProcessFromCommand -Command $cmd -Wait
            $app.IsSelected = $false
        }
        catch {
            try { Write-QLog ("Failed uninstall '{0}': {1}" -f $name, $_.Exception.Message) "ERROR" } catch { }
        }
    }
}

function Start-QOTProcessFromCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [switch]$Wait
    )

    $cmdArgs = @("/c", $Command)

    if ($Wait) {
        Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -Wait -WindowStyle Hidden
    }
    else {
        Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WindowStyle Hidden
    }
}

Export-ModuleMember -Function Initialize-QOTAppsUI
