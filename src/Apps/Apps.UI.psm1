# Apps.UI.psm1
# UI logic for the Apps tab (scan, uninstall, install common apps)

param()

Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force
Import-Module "$PSScriptRoot\InstalledApps.psm1"           -Force
Import-Module "$PSScriptRoot\InstallCommonApps.psm1"       -Force

try { Import-Module "$PSScriptRoot\..\UI\MainWindow.UI.psm1" -Force -ErrorAction SilentlyContinue } catch { }

if (-not $Global:QOT_InstalledAppsCollection) {
    $Global:QOT_InstalledAppsCollection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
}
if (-not $Global:QOT_CommonAppsCollection) {
    $Global:QOT_CommonAppsCollection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
}

function Update-QOTStatusSafe {
    param([string]$Text)

    try {
        if (Get-Command Set-QOTStatus -ErrorAction SilentlyContinue) {
            Set-QOTStatus -Text $Text
        } else {
            Write-QLog $Text
        }
    } catch {
        try { Write-QLog "Update-QOTStatusSafe error: $($_.Exception.Message)" "WARN" } catch { }
    }
}

function Refresh-QOTInstalledAppsGrid {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    Update-QOTStatusSafe "Scanning installed apps..."
    Write-QLog "Apps tab: started installed apps scan."

    $Global:QOT_InstalledAppsCollection.Clear()

    try {
        $apps = Get-QOTInstalledApps

        foreach ($app in $apps) {
            $row = [pscustomobject]@{
                IsSelected    = $false
                Name          = $app.Name
                Publisher     = $app.Publisher
                Uninstall     = $app.UninstallString
                IsWhitelisted = $app.IsWhitelisted
                Risk          = $app.Risk
                IsSelectable  = -not $app.IsWhitelisted -and
                                $app.Risk -ne "Red" -and
                                [bool]$app.UninstallString
            }

            $Global:QOT_InstalledAppsCollection.Add($row) | Out-Null
        }

        $Grid.ItemsSource = $Global:QOT_InstalledAppsCollection
        $Grid.Items.Refresh()

        Write-QLog "Apps tab: finished installed apps scan. Count: $($Global:QOT_InstalledAppsCollection.Count)"
        Update-QOTStatusSafe "Installed apps scan complete."
    }
    catch {
        $msg = $_.Exception.Message
        Write-QLog "Apps tab: error in Refresh-QOTInstalledAppsGrid: $msg" "ERROR"
        Update-QOTStatusSafe "Error scanning apps."
        [System.Windows.MessageBox]::Show("There was an error while scanning installed apps:`n`n$msg","Quinn Optimiser Toolkit",'OK','Error') | Out-Null
    }
}

function Refresh-QOTCommonAppsGrid {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    Update-QOTStatusSafe "Refreshing common apps list..."
    Write-QLog "Apps tab: refreshing common apps list."

    $Global:QOT_CommonAppsCollection.Clear()

    try {
        $apps = Get-QOTCommonApps

        foreach ($app in $apps) {
            if (-not ($app.PSObject.Properties.Name -contains "IsSelected")) {
                $app | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
            }
            $Global:QOT_CommonAppsCollection.Add($app) | Out-Null
        }

        $Grid.ItemsSource = $Global:QOT_CommonAppsCollection
        $Grid.Items.Refresh()

        Update-QOTStatusSafe "Common apps list updated."
    }
    catch {
        $msg = $_.Exception.Message
        Write-QLog "Apps tab: error in Refresh-QOTCommonAppsGrid: $msg" "ERROR"
        Update-QOTStatusSafe "Error loading common apps."
    }
}

function Invoke-QOTUninstallSelectedApps {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    $chosen = $Global:QOT_InstalledAppsCollection | Where-Object { $_.IsSelected }

    if (-not $chosen) { return }

    $toRemove = $chosen | Where-Object {
        -not ($_.IsWhitelisted -or $_.Risk -eq "Red" -or -not $_.Uninstall)
    }

    if (-not $toRemove) {
        [System.Windows.MessageBox]::Show(
            "All selected apps are protected or cannot be uninstalled.`n`nNothing will be uninstalled.",
            "Apps",
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    $names = ($toRemove.Name -join ", ")
    $confirm = [System.Windows.MessageBox]::Show(
        "Uninstall the following apps?`n`n$names",
        "Confirm uninstall",
        'YesNo',
        'Warning'
    )
    if ($confirm -ne 'Yes') { return }

    Update-QOTStatusSafe "Uninstalling selected apps..."
    Write-QLog "Apps tab: starting uninstall of selected apps: $names"

    foreach ($app in $toRemove) {
        try {
            $cmd = ($app.Uninstall).Trim()
            if (-not $cmd) { continue }

            Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -WindowStyle Hidden
            Write-QLog "Apps tab: uninstall completed for $($app.Name)"
        }
        catch {
            Write-QLog "Apps tab: uninstall failed for $($app.Name): $($_.Exception.Message)" "ERROR"
        }
    }

    Refresh-QOTInstalledAppsGrid -Grid $Grid
    Update-QOTStatusSafe "Uninstall complete."
}

function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    $chosen = $Global:QOT_CommonAppsCollection | Where-Object { $_.IsSelected -and $_.IsInstallable }
    if (-not $chosen) { return }

    $names = ($chosen.Name -join ", ")
    $confirm = [System.Windows.MessageBox]::Show(
        "Install the following apps?`n`n$names",
        "Confirm install",
        'YesNo',
        'Question'
    )
    if ($confirm -ne 'Yes') { return }

    Update-QOTStatusSafe "Installing selected apps..."
    Write-QLog "Apps tab: starting install of selected common apps: $names"

    foreach ($app in $chosen) {
        try {
            Install-QOTCommonApp -WingetId $app.WingetId -Name $app.Name | Out-Null
            Write-QLog "Apps tab: install completed for $($app.Name)"
        }
        catch {
            Write-QLog "Apps tab: install failed for $($app.Name): $($_.Exception.Message)" "ERROR"
        }
    }

    Refresh-QOTCommonAppsGrid -Grid $Grid
    Update-QOTStatusSafe "Install complete."
}

function Initialize-QOTAppsUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$BtnScanApps,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$BtnUninstallSelected,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$AppsGrid,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$InstallGrid,

        [Parameter(Mandatory = $false)]
        [System.Windows.Controls.Button]$RunButton
    )

    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    if ($RunButton) {
        $RunButton.Add_Click({
            Invoke-QOTUninstallSelectedApps -Grid $AppsGrid
            Invoke-QOTInstallSelectedCommonApps -Grid $InstallGrid
        })
    }

    Refresh-QOTInstalledAppsGrid -Grid $AppsGrid
    Refresh-QOTCommonAppsGrid    -Grid $InstallGrid

    Write-QLog "Apps tab UI initialised."
}

Export-ModuleMember -Function `
    Refresh-QOTInstalledAppsGrid, `
    Refresh-QOTCommonAppsGrid, `
    Invoke-QOTUninstallSelectedApps, `
    Invoke-QOTInstallSelectedCommonApps, `
    Initialize-QOTAppsUI
