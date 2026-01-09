# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab (self-contained: finds controls from Window)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\\..\\Core\\Actions\\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue


# Keep worker alive so async scan reliably completes
$script:QOT_InstalledAppsWorker = $null

function Initialize-QOTAppsUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    try {
        # Find controls from XAML
        $AppsGrid        = $Window.FindName("AppsGrid")
        $InstallGrid     = $Window.FindName("InstallGrid")
        $RunButton       = $Window.FindName("RunButton")

        if (-not $AppsGrid)    { try { Write-QLog "Apps UI: AppsGrid not found in XAML (x:Name='AppsGrid')." "ERROR" } catch { }; return }
        if (-not $InstallGrid) { try { Write-QLog "Apps UI: InstallGrid not found in XAML (x:Name='InstallGrid')." "ERROR" } catch { }; return }
        if (-not $RunButton)   { try { Write-QLog "Apps UI: RunButton not found in XAML (x:Name='RunButton')." "ERROR" } catch { }; return }

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

            if ($appsGrid) {
                $appsGridRef = $appsGrid
                $items += [pscustomobject]@{
                    Label = "Uninstall selected apps"
                    IsSelected = ({
                        param($window)
                        $apps = @($appsGridRef.ItemsSource)
                        (@($apps | Where-Object { $_.IsSelected -eq $true }).Count -gt 0)
                    }).GetNewClosure()
                    Execute = ({ param($window) Invoke-QOTUninstallSelectedApps -Grid $appsGridRef -Rescan }).GetNewClosure()
                }
            }

            if ($installGrid) {
                foreach ($app in @($installGrid.ItemsSource)) {
                    $appRef = $app
                    if (-not $appRef) { continue }
                    $items += [pscustomobject]@{
                        Id = if ($appRef.WingetId) { "InstallApp:$($appRef.WingetId)" } else { "InstallApp:$($appRef.Name)" }
                        Label = "Install: $($appRef.Name)"
                        IsSelected = ({
                            param($window)
                            $appRef.IsSelected -eq $true -and -not [string]::IsNullOrWhiteSpace($appRef.WingetId) -and $appRef.IsInstallable -ne $false
                        }).GetNewClosure()
                        Execute = ({ param($window) Invoke-QOTInstallCommonAppItem -App $appRef }).GetNewClosure()
                    }
                }
            }

            return $items
        }).GetNewClosure()

        try { Write-QLog "Apps tab UI initialised (Window based wiring)." "DEBUG" } catch { }
    }
    catch {
        try { Write-QLog ("Apps UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
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

function Start-QOTInstalledAppsScanAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [switch]$ForceScan
    )

    try {
        if (-not (Get-Command Get-QOTInstalledApps -ErrorAction SilentlyContinue)) {
            try { Write-QLog "Get-QOTInstalledApps not found. Check Apps\InstalledApps.psm1 was imported." "ERROR" } catch { }
            return
        }

        $dispatcher = $AppsGrid.Dispatcher

        if (-not $ForceScan -and (Get-Command Get-QOTInstalledAppsCached -ErrorAction SilentlyContinue)) {
            $cachedResults = @(Get-QOTInstalledAppsCached)
            $dispatcher.Invoke([action]{
                $Global:QOT_InstalledAppsCollection.Clear()
                foreach ($app in $cachedResults) {
                    Ensure-QOTInstalledAppForGrid -App $app
                    $Global:QOT_InstalledAppsCollection.Add($app)
                }
            })

            try { Write-QLog ("Installed apps loaded from cache ({0} items)." -f $cachedResults.Count) "DEBUG" } catch { }
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
                $Global:QOT_InstalledAppsCache = $results

                $dispatcher.Invoke([action]{
                    $Global:QOT_InstalledAppsCollection.Clear()
                    foreach ($app in $results) {
                        Ensure-QOTInstalledAppForGrid -App $app
                        $Global:QOT_InstalledAppsCollection.Add($app)
                    }
                })

                try { Write-QLog ("Installed apps scan complete. Loaded {0} items." -f $results.Count) "DEBUG" } catch { }
            }
            catch {
                try { Write-QLog ("Installed apps scan completion handler failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
            }
        }

        if (-not $script:QOT_InstalledAppsWorker.IsBusy) {
            try { Write-QLog "Starting installed apps scan (async)." "DEBUG" } catch { }
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
    if ($null -eq $App.PSObject.Properties["UninstallString"]) {
        $App | Add-Member -NotePropertyName UninstallString -NotePropertyValue "" -Force
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

function Invoke-QOTInstallCommonAppItem {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if (-not $App) { return }

    if (-not (Get-Command Install-QOTCommonApp -ErrorAction SilentlyContinue)) {
        throw "Install-QOTCommonApp not found. Check Apps\\InstallCommonApps.psm1 is imported."
    }

    if ([string]::IsNullOrWhiteSpace($App.WingetId)) {
        return
    }

    Install-QOTCommonApp -Name $App.Name -WingetId $App.WingetId
    $App.IsSelected = $false
}

function Invoke-QOTUninstallAppItem {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if (-not $App) { return }

    $name = $App.Name
    $cmd  = $App.UninstallString

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        try { Write-QLog ("Skipping uninstall for '{0}' because UninstallString is empty." -f $name) "WARN" } catch { }
        return
    }

    try {
        try { Write-QLog ("Uninstalling: {0}" -f $name) "DEBUG" } catch { }
        Start-QOTProcessFromCommand -Command $cmd -Wait
        $App.IsSelected = $false
    }
    catch {
        try { Write-QLog ("Failed uninstall '{0}': {1}" -f $name, $_.Exception.Message) "ERROR" } catch { }
    }
}


function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true -and -not [string]::IsNullOrWhiteSpace($_.WingetId) -and $_.IsInstallable -ne $false })

    if ($selected.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps selected." "DEBUG" } catch { }
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
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [switch]$Rescan
    )

    $items = @($Grid.ItemsSource)
    $selected = @($items | Where-Object { $_.IsSelected -eq $true })
    $didUninstall = $false

    if ($selected.Count -eq 0) {
        try { Write-QLog "Uninstall skipped. No installed apps selected." "DEBUG" } catch { }
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
            try { Write-QLog ("Uninstalling: {0}" -f $name) "DEBUG" } catch { }
            Start-QOTProcessFromCommand -Command $cmd -Wait
            $didUninstall = $true
            $app.IsSelected = $false
        }
        catch {
            try { Write-QLog ("Failed uninstall '{0}': {1}" -f $name, $_.Exception.Message) "ERROR" } catch { }
        }
    }

    if ($Rescan -and $didUninstall) {
        Start-QOTInstalledAppsScanAsync -AppsGrid $Grid -ForceScan
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

Export-ModuleMember -Function Initialize-QOTAppsUI
