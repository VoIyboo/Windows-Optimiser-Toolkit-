# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab (stable checkbox behaviour + async installed scan)

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

    # Hide old buttons (can remove from XAML later)
    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    Initialize-QOTAppsCollections

    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    Set-QOTGridDefaults -Grid $AppsGrid
    Set-QOTGridDefaults -Grid $InstallGrid

    Initialize-QOTAppsGridsColumns -AppsGrid $AppsGrid -InstallGrid $InstallGrid

    # Stable single click checkboxes (including untick)
    Enable-QOTSingleClickCheckboxes -Grid $AppsGrid
    Enable-QOTSingleClickCheckboxes -Grid $InstallGrid

    # Load common app catalogue instantly (no winget list here)
    Initialize-QOTCommonAppsCatalogue

    # Installed apps scan (async so UI stays responsive)
    Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid

    if ($RunButton) {
        $RunButton.Add_Click({
            Commit-QOTGridEdits -Grid $AppsGrid
            Commit-QOTGridEdits -Grid $InstallGrid

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

function Set-QOTGridDefaults {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    $Grid.AutoGenerateColumns = $false
    $Grid.CanUserAddRows      = $false
    $Grid.IsReadOnly          = $false

    # Reduce focus/selection fighting
    $Grid.SelectionUnit = 'FullRow'
    $Grid.SelectionMode = 'Single'
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

function Enable-QOTSingleClickCheckboxes {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    # When clicking a checkbox, begin edit, then commit AFTER WPF toggles it
    $Grid.AddHandler(
        [System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent,
        [System.Windows.Input.MouseButtonEventHandler]{
            param($sender, $e)

            try {
                $dep = $e.OriginalSource
                while ($dep -and -not ($dep -is [System.Windows.Controls.CheckBox])) {
                    $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
                }

                if ($dep -is [System.Windows.Controls.CheckBox]) {
                    $null = $sender.BeginEdit()

                    # Commit later, after the click toggles IsChecked
                    $null = $sender.Dispatcher.BeginInvoke([action]{
                        try {
                            $null = $sender.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
                            $null = $sender.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true)
                        } catch { }
                    }, [System.Windows.Threading.DispatcherPriority]::Background)
                }
            } catch { }
        },
        $true
    )
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
    # Checkbox + App only (no Version)
    # -------------------------
    $InstallGrid.Columns.Clear()

    $InstallGrid.Columns.Add((New-QOTCheckBoxColumn -BindingPath "IsSelected" -Width 40))

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "App"
        Binding    = (New-Object System.Windows.Data.Binding "Name")
        Width      = "*"
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
            try { Write-QLog "Installed apps scan started (async)." "DEBUG" } catch { }
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
                try { Write-QLog ("Installed apps scan completed. Count={0}" -f $results.Count) "DEBUG" } catch { }

                $dispatcher.Invoke([action]{
                    $Global:QOT_InstalledAppsCollection.Clear()
                    foreach ($app in $results) {
                        Ensure-QOTInstalledAppForGrid -App $app
                        $Global:QOT_InstalledAppsCollection.Add($app)
                    }
                })

                try { Write-QLog ("Installed apps UI populated. Count={0}" -f $Global:QOT_InstalledAppsCollection.Count) "DEBUG" } catch { }
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
    if ($null -eq $App.PSObject.Properties["Version"]) {
        $App | Add-Member -NotePropertyName Version -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["Publisher"]) {
        $App | Add-Member -NotePropertyName Publisher -NotePropertyValue "" -Force
    }
}

function Initialize-QOTCommonAppsCatalogue {

    $catalogue = $null

    $cmd = Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue
    if ($cmd) {
        $catalogue = @(Get-QOTCommonAppsCatalogue)
    }
    else {
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
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    Commit-QOTGridEdits -Grid $Grid

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true -and -not [string]::IsNullOrWhiteSpace($_.WingetId) })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps selected." } catch { }
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
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    Commit-QOTGridEdits -Grid $Grid

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
