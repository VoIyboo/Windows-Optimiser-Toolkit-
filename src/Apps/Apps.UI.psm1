# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab

$ErrorActionPreference = "Stop"

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

    # Hide legacy buttons (you can remove them from XAML later)
    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    Initialize-QOTAppsCollections

    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    Initialize-QOTAppsGridsColumns -AppsGrid $AppsGrid -InstallGrid $InstallGrid

    # Fix 2: Commit checkbox edits instantly so it is never "double click to select"
    Enable-QOTImmediateCheckboxCommit -Grid $AppsGrid
    Enable-QOTImmediateCheckboxCommit -Grid $InstallGrid

    # Common apps list should be instant and static
    Initialize-QOTCommonAppsCatalogue

    # Installed apps scan should not freeze UI
    Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid

    if ($RunButton) {
        $RunButton.Add_Click({
            try { Invoke-QOTUninstallSelectedApps -Grid $AppsGrid } catch { try { Write-QLog ("Uninstall failed: {0}" -f $_.Exception.Message) "ERROR" } catch { } }
            try { Invoke-QOTInstallSelectedCommonApps -Grid $InstallGrid } catch { try { Write-QLog ("Install failed: {0}" -f $_.Exception.Message) "ERROR" } catch { } }
        })
    }

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

function Enable-QOTImmediateCheckboxCommit {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    $Grid.Add_CurrentCellChanged({
        try {
            $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
            $Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true) | Out-Null
        } catch { }
    })
}

function Initialize-QOTAppsGridsColumns {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$InstallGrid
    )

    # -------------------------
    # Installed Apps grid
    # -------------------------
    $AppsGrid.AutoGenerateColumns = $false
    $AppsGrid.CanUserAddRows      = $false
    $AppsGrid.IsReadOnly          = $false
    $AppsGrid.Columns.Clear()

    $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridCheckBoxColumn -Property @{
        Header  = ""
        Binding = (New-Object System.Windows.Data.Binding "IsSelected")
        Width   = 40
    }))

    $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "Name"
        Binding    = (New-Object System.Windows.Data.Binding "Name")
        Width      = "*"
        IsReadOnly = $true
    }))

    $AppsGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "Version"
        Binding    = (New-Object System.Windows.Data.Binding "Version")
        Width      = 140
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
    # Single click checkbox + App only
    # -------------------------
    $InstallGrid.AutoGenerateColumns = $false
    $InstallGrid.CanUserAddRows      = $false
    $InstallGrid.IsReadOnly          = $false
    $InstallGrid.Columns.Clear()

    # TemplateColumn checkbox (best behaviour)
    $checkFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.CheckBox])
    $checkFactory.SetValue([System.Windows.Controls.CheckBox]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
    $checkFactory.SetValue([System.Windows.Controls.CheckBox]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)

    $binding = New-Object System.Windows.Data.Binding("IsSelected")
    $binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
    $binding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged
    $checkFactory.SetBinding([System.Windows.Controls.CheckBox]::IsCheckedProperty, $binding)

    $cellTemplate = New-Object System.Windows.DataTemplate
    $cellTemplate.VisualTree = $checkFactory

    $colCheck = New-Object System.Windows.Controls.DataGridTemplateColumn
    $colCheck.Header = ""
    $colCheck.Width  = 40
    $colCheck.CellTemplate = $cellTemplate
    $colCheck.CellEditingTemplate = $cellTemplate
    $InstallGrid.Columns.Add($colCheck)

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "App"
        Binding    = (New-Object System.Windows.Data.Binding "Name")
        Width      = "*"
        IsReadOnly = $true
    }))
}

function Start-QOTInstalledAppsScanAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid
    )

    try {
        $dispatcher = $AppsGrid.Dispatcher

        $bw = New-Object System.ComponentModel.BackgroundWorker
        $bw.WorkerReportsProgress = $false
        $bw.WorkerSupportsCancellation = $false

        $bw.DoWork += {
            param($sender, $e)
            $e.Result = Get-QOTInstalledApps
        }

        $bw.RunWorkerCompleted += {
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

                try { Write-QLog ("Installed apps scan complete. Loaded {0} items." -f $results.Count) } catch { }
            }
            catch {
                try { Write-QLog ("Installed apps scan post processing failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
            }
        }

        if (-not $bw.IsBusy) {
            try { Write-QLog "Starting installed apps scan (async)." } catch { }
            $bw.RunWorkerAsync() | Out-Null
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
    if ($null -eq $App.PSObject.Properties["Version"]) {
        $App | Add-Member -NotePropertyName Version -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["Publisher"]) {
        $App | Add-Member -NotePropertyName Publisher -NotePropertyValue "" -Force
    }
}

function Initialize-QOTCommonAppsCatalogue {

    # Prefer catalogue from InstallCommonApps.psm1 if available
    $catalogue = $null
    $cmd = Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue
    if ($cmd) {
        $catalogue = @(Get-QOTCommonAppsCatalogue)
    } else {
        $catalogue = @(
            [pscustomobject]@{ IsSelected=$false; Name="Google Chrome";        WingetId="Google.Chrome";               Category="Browser" }
            [pscustomobject]@{ IsSelected=$false; Name="Microsoft Edge";       WingetId="Microsoft.Edge";              Category="Browser" }
            [pscustomobject]@{ IsSelected=$false; Name="7-Zip";                WingetId="7zip.7zip";                   Category="Utility" }
            [pscustomobject]@{ IsSelected=$false; Name="Notepad++";            WingetId="Notepad++.Notepad++";         Category="Utility" }
            [pscustomobject]@{ IsSelected=$false; Name="VLC Media Player";     WingetId="VideoLAN.VLC";                Category="Media" }
            [pscustomobject]@{ IsSelected=$false; Name="Git";                  WingetId="Git.Git";                     Category="Dev" }
            [pscustomobject]@{ IsSelected=$false; Name="Visual Studio Code";   WingetId="Microsoft.VisualStudioCode";  Category="Dev" }
            [pscustomobject]@{ IsSelected=$false; Name="Adobe Acrobat Reader"; WingetId="Adobe.Acrobat.Reader.64-bit"; Category="Utility" }
        )
    }

    $Global:QOT_CommonAppsCollection.Clear()
    foreach ($item in $catalogue) {
        if ($null -eq $item.PSObject.Properties["IsSelected"]) {
            $item | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
        }
        $Global:QOT_CommonAppsCollection.Add($item)
    }

    try { Write-QLog ("Common apps catalogue loaded ({0} items)." -f $Global:QOT_CommonAppsCollection.Count) } catch { }
}

function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true -and -not [string]::IsNullOrWhiteSpace($_.WingetId) })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps selected." } catch { }
        return
    }

    foreach ($app in $selected) {
        try {
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

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Uninstall skipped. No installed apps selected." } catch { }
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
            try { Write-QLog ("Uninstalling: {0}" -f $name) } catch { }
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
