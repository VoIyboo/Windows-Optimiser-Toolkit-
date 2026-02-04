# src\Apps\Apps.Actions.psm1
# Backend action handlers for Apps tab selections

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\Apps.Helpers.psm1" -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\InstallCommonApps.psm1" -Force -ErrorAction SilentlyContinue

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

Export-ModuleMember -Function Get-QOTSilentUninstallCommand, Start-QOTProcessFromCommand, Invoke-QOTInstallCommonAppItem, Invoke-QOTUninstallAppItem, Invoke-QOTRunSelectedAppsActions, Invoke-QOTInstallSelectedCommonApps, Invoke-QOTUninstallSelectedApps
