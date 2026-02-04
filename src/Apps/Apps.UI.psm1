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
        # Ensure Apps data modules are available even when UI is loaded standalone
        Import-Module (Join-Path $PSScriptRoot "InstalledApps.psm1")     -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $PSScriptRoot "InstallCommonApps.psm1") -Force -ErrorAction SilentlyContinue
        # Find controls from XAML
        $AppsGrid        = $Window.FindName("AppsGrid")
        $InstallGrid     = $Window.FindName("InstallGrid")
        $RunButton       = $Window.FindName("RunButton")
        $StatusLabel     = $Window.FindName("StatusLabel")

        if (-not $AppsGrid)    { try { Write-QLog "Apps UI: AppsGrid not found in XAML (x:Name='AppsGrid')." "ERROR" } catch { }; return $false }
        if (-not $InstallGrid) { try { Write-QLog "Apps UI: InstallGrid not found in XAML (x:Name='InstallGrid')." "ERROR" } catch { }; return $false }
        if (-not $RunButton)   { try { Write-QLog "Apps UI: RunButton not found in XAML (x:Name='RunButton')." "ERROR" } catch { }; return $false }

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

function Get-QOTNormalizedAppName {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    $normalized = $Name.ToLowerInvariant()
    $normalized = $normalized -replace "[^a-z0-9]", ""
    return $normalized
}

function Get-QOTInstalledAppNameSet {
    param(
        [Parameter(Mandatory)][object[]]$Apps
    )

    $set = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($app in $Apps) {
        if (-not $app) { continue }
        $key = Get-QOTNormalizedAppName -Name $app.Name
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            [void]$set.Add($key)
        }
    }

    return $set
}

function Update-QOTCommonAppsInstallStatus {
    param(
        [Parameter(Mandatory)][object[]]$InstalledApps
    )

    $commonApps = @($Global:QOT_CommonAppsCollection)
    if (-not $commonApps -or $commonApps.Count -eq 0) { return }

    $installedNameSet = Get-QOTInstalledAppNameSet -Apps $InstalledApps

    foreach ($item in $commonApps) {
        if (-not $item) { continue }
        $installed = $false
        if (-not [string]::IsNullOrWhiteSpace($item.Name)) {
            $key = Get-QOTNormalizedAppName -Name $item.Name
            if ($installedNameSet.Contains($key)) { $installed = $true }
        }

        if ($null -eq $item.PSObject.Properties["Status"]) {
            $item | Add-Member -NotePropertyName Status -NotePropertyValue "" -Force
        }
        if ($null -eq $item.PSObject.Properties["IsInstallable"]) {
            $item | Add-Member -NotePropertyName IsInstallable -NotePropertyValue $true -Force
        }

        $item.Status = if ($installed) { "Installed" } else { "Available" }
        $item.IsInstallable = -not $installed
    }
}

function Set-QOTAppsStatus {
    param(
        [System.Windows.Controls.TextBlock]$StatusLabel,
        [string]$Text
    )

    if (-not $StatusLabel -or [string]::IsNullOrWhiteSpace($Text)) { return }

    try {
        $StatusLabel.Dispatcher.Invoke([action]{ $StatusLabel.Text = $Text })
    } catch {
        try { $StatusLabel.Text = $Text } catch { }
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

function Start-QOTInstalledAppsScanAsync {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [switch]$ForceScan
    )

    try {
        if (-not (Get-Command Get-QOTInstalledApps -ErrorAction SilentlyContinue)) {
            Import-Module (Join-Path $PSScriptRoot "InstalledApps.psm1") -Force -ErrorAction SilentlyContinue
        }
        if (-not (Get-Command Get-QOTInstalledApps -ErrorAction SilentlyContinue)) {
            try { Write-QLog "Get-QOTInstalledApps not found. Check Apps\InstalledApps.psm1 was imported." "ERROR" } catch { }
            return
        }

        $dispatcher = $AppsGrid.Dispatcher

        if (-not $ForceScan -and $Global:QOT_InstalledAppsCache -and $Global:QOT_InstalledAppsCache.Count -gt 0) {
            $cachedResults = @($Global:QOT_InstalledAppsCache)
            $dispatcher.Invoke([action]{
                $Global:QOT_InstalledAppsCollection.Clear()
                foreach ($app in $cachedResults) {
                    Ensure-QOTInstalledAppForGrid -App $app
                    $Global:QOT_InstalledAppsCollection.Add($app)
                }
            })

            Update-QOTCommonAppsInstallStatus -InstalledApps $cachedResults

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

function Get-QOTSilentUninstallCommand {
    param(
        [Parameter(Mandatory)][object]$App
    )

    $cmd = $App.UninstallString
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }

    if ($cmd -match "(?i)msiexec") {
        $cmd = $cmd -replace "(?i)\\s/I\\b", " /X"
        if ($cmd -notmatch "(?i)\\s/(qn|quiet)\\b") {
            $cmd = "$cmd /qn /norestart"
        }
    }

    return $cmd
}

function Invoke-QOTUninstallAppItem {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if (-not $App) { return }

    $name = $App.Name
    $cmd  = Get-QOTSilentUninstallCommand -App $App

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

function Invoke-QOTRunSelectedAppsActions {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$InstallGrid,
        [System.Windows.Controls.TextBlock]$StatusLabel
    )

    Commit-QOTGridEdits -Grid $AppsGrid
    Commit-QOTGridEdits -Grid $InstallGrid

    $installedItems = @($AppsGrid.ItemsSource)
    $commonItems = @($InstallGrid.ItemsSource)

    $selectedInstalled = @($installedItems | Where-Object { $_.IsSelected -eq $true })
    $selectedCommon = @($commonItems | Where-Object { $_.IsSelected -eq $true -and $_.IsInstallable -ne $false })

    if ($selectedInstalled.Count -eq 0 -and $selectedCommon.Count -eq 0) {
        try { Write-QLog "Apps actions skipped. Nothing selected." "INFO" } catch { }
        Set-QOTAppsStatus -StatusLabel $StatusLabel -Text "Idle"
        return
    }

    $installedNameSet = Get-QOTInstalledAppNameSet -Apps $installedItems
    $selectedInstalledNameSet = Get-QOTInstalledAppNameSet -Apps $selectedInstalled
    $selectedCommonNameSet = Get-QOTInstalledAppNameSet -Apps $selectedCommon

    $overlap = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $selectedInstalledNameSet) {
        if ($selectedCommonNameSet.Contains($name)) {
            [void]$overlap.Add($name)
        }
    }

    if ($overlap.Count -gt 0) {
        foreach ($name in $overlap) {
            try { Write-QLog ("App appears in both install and uninstall selections. Skipping '{0}'." -f $name) "WARN" } catch { }
        }
        $selectedInstalled = @($selectedInstalled | Where-Object { -not $overlap.Contains((Get-QOTNormalizedAppName -Name $_.Name)) })
        $selectedCommon = @($selectedCommon | Where-Object { -not $overlap.Contains((Get-QOTNormalizedAppName -Name $_.Name)) })
    }

    $didChange = $false

    foreach ($app in $selectedInstalled) {
        $name = $app.Name
        $key = Get-QOTNormalizedAppName -Name $name
        if (-not $installedNameSet.Contains($key)) {
            try { Write-QLog ("Skipping uninstall for '{0}' because it no longer appears installed." -f $name) "WARN" } catch { }
            continue
        }

        $cmd = Get-QOTSilentUninstallCommand -App $app
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            try { Write-QLog ("Skipping uninstall for '{0}' because no uninstall command is available." -f $name) "WARN" } catch { }
            continue
        }

        Set-QOTAppsStatus -StatusLabel $StatusLabel -Text ("Uninstalling {0}..." -f $name)
        try {
            Start-QOTProcessFromCommand -Command $cmd -Wait
            $app.IsSelected = $false
            $didChange = $true
            try { Write-QLog ("Uninstall succeeded: {0}" -f $name) "INFO" } catch { }
        }
        catch {
            try { Write-QLog ("Failed uninstall '{0}': {1}" -f $name, $_.Exception.Message) "ERROR" } catch { }
        }
    }

    foreach ($app in $selectedCommon) {
        $name = $app.Name
        $key = Get-QOTNormalizedAppName -Name $name

        $alreadyInstalled = $false
        if ($installedNameSet.Contains($key)) { $alreadyInstalled = $true }
        if (-not $alreadyInstalled -and (Get-Command Test-QOTWingetAppInstalled -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace($app.WingetId)) {
            try { $alreadyInstalled = Test-QOTWingetAppInstalled -WingetId $app.WingetId } catch { $alreadyInstalled = $false }
        }

        if ($alreadyInstalled) {
            $app.Status = "Installed"
            $app.IsInstallable = $false
            $app.IsSelected = $false
            try { Write-QLog ("Skipping install for '{0}' because it is already installed." -f $name) "INFO" } catch { }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($app.WingetId)) {
            try { Write-QLog ("Skipping install for '{0}' because WingetId is missing." -f $name) "WARN" } catch { }
            continue
        }

        Set-QOTAppsStatus -StatusLabel $StatusLabel -Text ("Installing {0}..." -f $name)
        try {
            Install-QOTCommonApp -Name $app.Name -WingetId $app.WingetId
            $app.Status = "Installed"
            $app.IsInstallable = $false
            $app.IsSelected = $false
            $didChange = $true
            try { Write-QLog ("Install succeeded: {0}" -f $name) "INFO" } catch { }
        }
        catch {
            $app.Status = "Failed"
            try { Write-QLog ("Install failed for '{0}': {1}" -f $name, $_.Exception.Message) "ERROR" } catch { }
        }
    }

    Set-QOTAppsStatus -StatusLabel $StatusLabel -Text "Refreshing apps..."
    if ($didChange) {
        Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid -ForceScan
    } else {
        Update-QOTCommonAppsInstallStatus -InstalledApps $installedItems
    }
    Set-QOTAppsStatus -StatusLabel $StatusLabel -Text "Idle"
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
        $cmd  = Get-QOTSilentUninstallCommand -App $app

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
