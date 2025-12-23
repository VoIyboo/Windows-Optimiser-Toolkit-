# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab

$ErrorActionPreference = "Stop"

# Keep worker alive so async scan reliably completes
$script:QOT_InstalledAppsWorker = $null

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

    try { Write-QLog "Apps UI: Initialize-QOTAppsUI CALLED" "INFO" } catch { }

    # Hide legacy buttons (leave them in XAML if you want)
    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    Initialize-QOTAppsCollections

    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    Set-QOTGridDefaults -Grid $AppsGrid
    Set-QOTGridDefaults -Grid $InstallGrid

    Initialize-QOTAppsGridsColumns -AppsGrid $AppsGrid -InstallGrid $InstallGrid

    # Load common catalogue instantly (no winget list here)
    Initialize-QOTCommonAppsCatalogue

    # Auto scan installed apps (async so UI stays responsive)
    Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid

    if ($RunButton) {
        $RunButton.Add_Click({
            Commit-QOTGridEdits -Grid $AppsGrid
            Commit-QOTGridEdits -Grid $InstallGrid

            try { Invoke-QOTUninstallSelectedApps -Grid $AppsGrid } catch { try { Write-QLog ("Uninstall failed: {0}" -f $_.Exception.Message) "ERROR" } catch { } }
            try { Invoke-QOTInstallSelectedCommonApps -Grid $InstallGrid } catch { try { Write-QLog ("Install failed: {0}" -f $_.Exception.Message) "ERROR" } catch { } }
        })
    }

    try { Write-QLog "Apps tab UI initialised." "INFO" } catch { }
}

function Initialize-QOTAppsCollections {
    if (-not $Global:QOT_InstalledAppsCollection) {
        $Global:QOT_InstalledAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
    if (-not $Global:QOT_CommonAppsCollection) {
        $Global:QOT_CommonAppsCollection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
}

function Set-QOTGridDefaults {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    $Grid.AutoGenerateColumns = $false
    $Grid.CanUserAddRows      = $false
    $Grid.IsReadOnly          = $false
    $Grid.SelectionUnit       = 'FullRow'
    $Grid.SelectionMode       = 'Single'
    $Grid.IsSynchronizedWithCurrentItem = $false
}

function Commit-QOTGridEdits {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    try {
        $null = $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        $null = $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true)
    } catch { }
}

function New-QOTCheckBoxColumn {
    param(
        [Parameter(Mandatory)]
        [string]$BindingPath,
        [int]$Width = 40
    )

    $bind = New-Object System.Windows.Data.Binding($BindingPath)
    $bind.Mode = [System.Windows.Data.BindingMode]::TwoWay
    $bind.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged

    $col = New-Object System.Windows.Controls.DataGridCheckBoxColumn
    $col.Header  = ""
    $col.Width   = $Width
    $col.Binding = $bind
    $col.IsThreeState = $false
    return $col
}

function Initialize-QOTAppsGridsColumns {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$InstallGrid
    )

    # -------------------------
    # Installed Apps grid
    # -------------------------
    $AppsGrid.Columns.Clear()

    $AppsGrid.Columns.Add((New-QOTCheckBoxColumn -BindingPath "IsSelected" -Width 40))

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

    # -------------------------
    # Common Apps grid
    # Checkbox + App + Status
    # -------------------------
    $InstallGrid.Columns.Clear()

    $InstallGrid.Columns.Add((New-QOTCheckBoxColumn -BindingPath "IsSelected" -Width 40))

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "App"
        Binding    = (New-Object System.Windows.Data.Binding "Name")
        Width      = "*"
        IsReadOnly = $true
    }))

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "Status"
        Binding    = (New-Object System.Windows.Data.Binding "Status")
        Width      = 140
        IsReadOnly = $true
    }))
}

function Start-QOTInstalledAppsScanAsync {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$AppsGrid
    )

    try {
        $dispatcher = $AppsGrid.Dispatcher

        if (-not (Get-Command Get-QOTInstalledApps -ErrorAction SilentlyContinue)) {
            try { Write-QLog "Get-QOTInstalledApps not found. Check Apps\InstalledApps.psm1 is imported." "ERROR" } catch { }
            return
        }

        $script:QOT_InstalledAppsWorker = New-Object System.ComponentModel.BackgroundWorker
        $script:QOT_InstalledAppsWorker.WorkerReportsProgress = $false
        $script:QOT_InstalledAppsWorker.WorkerSupportsCancellation = $false

        $script:QOT_InstalledAppsWorker.DoWork += {
            param($sender, $e)
            $e.Result = @(Get-QOTInstalledApps)
        }

        $script:QOT_InstalledAppsWorker.RunWorkerCompleted += {
            param($sender, $e)

            try {
                if ($e.Error) {
                    try { Write-QLog ("Installed apps scan failed: {0}" -f $e.Error.Message) "ERROR" } catch { }
                    return
                }

                $results = @($e.Result)

                $dispatcher.Invoke([action]{
                    $Global:QOT_InstalledAppsCollection.Clear()

                    foreach ($app in $results) {
                        Ensure-QOTInstalledAppForGrid -App $app
                        $Global:QOT_InstalledAppsCollection.Add($app)
                    }
                })

                try { Write-QLog ("Installed apps scan complete. Loaded {0} items." -f $results.Count) "INFO" } catch { }
            }
            catch {
                try { Write-QLog ("Installed apps completion handler failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
            }
        }

        if (-not $script:QOT_InstalledAppsWorker.IsBusy) {
            $script:QOT_InstalledAppsWorker.RunWorkerAsync() | Out-Null
        }
    }
    catch {
        try { Write-QLog ("Start-QOTInstalledAppsScanAsync error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

function Ensure-QOTInstalledAppForGrid {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if ($null -eq $App.PSObject.Properties["IsSelected"]) {
        $App | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
    }
    if ($null -eq $App.PSObject.Properties["Publisher"]) {
        $App | Add-Member -NotePropertyName Publisher -NotePropertyValue "" -Force
    }
}

function Initialize-QOTCommonAppsCatalogue {

    $catalogue = @()

    if (Get-Command Get-QOTCommonApps -ErrorAction SilentlyContinue) {
        $catalogue = @(Get-QOTCommonApps)
    }
    elseif (Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue) {
        $catalogue = @(Get-QOTCommonAppsCatalogue)
        foreach ($a in $catalogue) {
            if ($null -eq $a.PSObject.Properties["Status"]) {
                $a | Add-Member -NotePropertyName Status -NotePropertyValue "Available" -Force
            }
            if ($null -eq $a.PSObject.Properties["IsSelected"]) {
                $a | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
            }
        }
    }
    else {
        $catalogue = @(
            [pscustomobject]@{ IsSelected=$false; Name="Google Chrome";        WingetId="Google.Chrome";               Status="Available" }
            [pscustomobject]@{ IsSelected=$false; Name="Microsoft Edge";       WingetId="Microsoft.Edge";              Status="Available" }
            [pscustomobject]@{ IsSelected=$false; Name="7-Zip";                WingetId="7zip.7zip";                   Status="Available" }
            [pscustomobject]@{ IsSelected=$false; Name="Notepad++";            WingetId="Notepad++.Notepad++";         Status="Available" }
            [pscustomobject]@{ IsSelected=$false; Name="VLC Media Player";     WingetId="VideoLAN.VLC";                Status="Available" }
            [pscustomobject]@{ IsSelected=$false; Name="Git";                  WingetId="Git.Git";                     Status="Available" }
            [pscustomobject]@{ IsSelected=$false; Name="Visual Studio Code";   WingetId="Microsoft.VisualStudioCode";  Status="Available" }
            [pscustomobject]@{ IsSelected=$false; Name="Adobe Acrobat Reader"; WingetId="Adobe.Acrobat.Reader.64-bit"; Status="Available" }
        )
    }

    $Global:QOT_CommonAppsCollection.Clear()
    foreach ($item in $catalogue) {
        if ($null -eq $item.PSObject.Properties["IsSelected"]) {
            $item | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
        }
        if ($null -eq $item.PSObject.Properties["Status"]) {
            $item | Add-Member -NotePropertyName Status -NotePropertyValue "Available" -Force
        }
        $Global:QOT_CommonAppsCollection.Add($item)
    }

    try { Write-QLog ("Common apps loaded ({0} items)." -f $Global:QOT_CommonAppsCollection.Count) "INFO" } catch { }
}

function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    Commit-QOTGridEdits -Grid $Grid

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true -and -not [string]::IsNullOrWhiteSpace($_.WingetId) })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps selected." "INFO" } catch { }
        return
    }

    foreach ($app in $selected) {
        try {
            if (-not (Get-Command Install-QOTCommonApp -ErrorAction SilentlyContinue)) {
                throw "Install-QOTCommonApp not found. Check Apps\InstallCommonApps.psm1 is imported."
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
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    Commit-QOTGridEdits -Grid $Grid

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
        [Parameter(Mandatory)][string]$Command,
        [switch]$Wait
    )

    $cmdArgs = @("/c", $Command)

    if ($Wait) {
        Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -Wait -WindowStyle Hidden
    } else {
        Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WindowStyle Hidden
    }
}

Export-ModuleMember -Function `
    Initialize-QOTAppsUI
