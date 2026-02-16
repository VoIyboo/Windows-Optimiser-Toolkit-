# src\Apps\Apps.Helpers.psm1
# Shared helpers for Apps UI and actions

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue

$script:QOT_InstalledAppsWorker = $null

function Commit-QOTGridEdits {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
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

function Get-QOTInstalledAppDataset {
    param(
        [Parameter(Mandatory)][object[]]$Apps
    )

    $win32NameSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    $storeNameSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($app in $Apps) {
        if (-not $app) { continue }

        $name = $null
        try { $name = $app.Name } catch { $name = $null }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $source = "Win32"
        try {
            if (-not [string]::IsNullOrWhiteSpace($app.Source)) {
                $source = [string]$app.Source
            }
        } catch { }

        if ($source -ieq "Store") {
            [void]$storeNameSet.Add($name)
        }
        else {
            [void]$win32NameSet.Add($name)
        }
    }

    return [pscustomobject]@{
        AllNames    = Get-QOTInstalledAppNameSet -Apps $Apps
        Win32Names  = $win32NameSet
        StoreNames  = $storeNameSet
    }
}

function Test-QOTCommonAppInstalled {
    param(
        [Parameter(Mandatory)][object]$CommonApp,
        [Parameter(Mandatory)][object]$InstalledDataset
    )

    $name = $null
    try { $name = [string]$CommonApp.Name } catch { $name = $null }
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }

    $normalizedName = Get-QOTNormalizedAppName -Name $name

    if ($InstalledDataset.AllNames.Contains($normalizedName)) {
        return $true
    }

    $storePackageName = $null
    try { $storePackageName = [string]$CommonApp.PackageName } catch { $storePackageName = $null }
    if (-not [string]::IsNullOrWhiteSpace($storePackageName) -and $InstalledDataset.StoreNames.Contains($storePackageName)) {
        return $true
    }

    $wingetId = $null
    try { $wingetId = [string]$CommonApp.WingetId } catch { $wingetId = $null }

    if (-not [string]::IsNullOrWhiteSpace($wingetId) -and $InstalledDataset.StoreNames.Contains($wingetId)) {
        return $true
    }

    return $false
}


function Update-QOTCommonAppsInstallStatus {
    param(
        [Parameter(Mandatory)][object[]]$InstalledApps
    )

    $commonApps = @($Global:QOT_CommonAppsCollection)
    if (-not $commonApps -or $commonApps.Count -eq 0) { return }

    $dataset = Get-QOTInstalledAppDataset -Apps $InstalledApps

    foreach ($item in $commonApps) {
        if (-not $item) { continue }
        $installed = Test-QOTCommonAppInstalled -CommonApp $item -InstalledDataset $dataset

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
    if ($null -eq $App.PSObject.Properties["Version"]) {
        $App | Add-Member -NotePropertyName Version -NotePropertyValue "" -Force
    }
    if ($null -eq $App.PSObject.Properties["Source"]) {
        $App | Add-Member -NotePropertyName Source -NotePropertyValue "Win32" -Force
    }
    if ($null -eq $App.PSObject.Properties["InstallDate"]) {
        $App | Add-Member -NotePropertyName InstallDate -NotePropertyValue $null -Force
    }
    
    if ($null -eq $App.PSObject.Properties["UninstallString"]) {
        $App | Add-Member -NotePropertyName UninstallString -NotePropertyValue "" -Force
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

        if ($script:QOT_InstalledAppsWorker) {
            try { $script:QOT_InstalledAppsWorker.Dispose() } catch { }
        }

        $script:QOT_InstalledAppsWorker = New-Object System.ComponentModel.BackgroundWorker
        $script:QOT_InstalledAppsWorker.WorkerReportsProgress = $false
        $script:QOT_InstalledAppsWorker.WorkerSupportsCancellation = $false

        $script:QOT_InstalledAppsWorker.add_DoWork({
            param($sender, $e)
            $e.Result = @(Get-QOTInstalledAppsCached -ForceRefresh:$ForceScan)
        })

        $script:QOT_InstalledAppsWorker.add_RunWorkerCompleted({
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
                Update-QOTCommonAppsInstallStatus -InstalledApps $results
                try { Write-QLog ("Installed apps scan complete. Loaded {0} items." -f $results.Count) "DEBUG" } catch { }
            }
            catch {
                try { Write-QLog ("Installed apps scan completion handler failed: {0}" -f $_.Exception.Message) "ERROR" } catch { }
            }
        })

        if (-not $script:QOT_InstalledAppsWorker.IsBusy) {
            try { Write-QLog "Starting installed apps scan (async)." "DEBUG" } catch { }
            $script:QOT_InstalledAppsWorker.RunWorkerAsync() | Out-Null
        }
    }
    catch {
        try { Write-QLog ("Start-QOTInstalledAppsScanAsync error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

Export-ModuleMember -Function Commit-QOTGridEdits, Get-QOTNormalizedAppName, Get-QOTInstalledAppNameSet, Get-QOTInstalledAppDataset, Test-QOTCommonAppInstalled, Update-QOTCommonAppsInstallStatus, Set-QOTAppsStatus, Ensure-QOTInstalledAppForGrid, Start-QOTInstalledAppsScanAsync
