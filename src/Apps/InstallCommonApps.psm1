# InstallCommonApps.psm1
# Handles the catalogue and winget-based install of common apps

# Import core modules (relative to src\Apps)
Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force

function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    $chosen = $Global:QOT_CommonAppsCollection | Where-Object { $_.IsSelected -and $_.IsInstallable }

    if (-not $chosen) {
        return
    }

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

    $count = $chosen.Count
    if ($count -lt 1) { $count = 1 }
    $index = 0
    $failures = @()

    foreach ($app in $chosen) {
        $index++
        Update-QOTStatusSafe ("Installing {0} ({1}/{2})" -f $app.Name, $index, $count)

        try {
            Install-QOTCommonApp -WingetId $app.WingetId -Name $app.Name | Out-Null
            Write-QLog "Apps tab: install completed for $($app.Name)"
        }
        catch {
            $failures += $app.Name
            Write-QLog "Apps tab: install failed for $($app.Name): $($_.Exception.Message)" "ERROR"
        }
    }

    Refresh-QOTCommonAppsGrid -Grid $Grid
    Update-QOTStatusSafe "Install complete."

    if ($failures.Count -gt 0) {
        [System.Windows.MessageBox]::Show(
            "Some apps could not be installed:`n`n$($failures -join ', ')`n`nCheck the log for details.",
            "Apps",
            'OK',
            'Warning'
        ) | Out-Null
    }
}

function Initialize-QOTAppsUI {
    <#
        Wires up the Apps tab controls.
        Run selected actions should handle both uninstall and installs.
    #>
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

    # Kill the old uninstall button click if it still exists (belt and braces)
    try { $BtnUninstallSelected.Remove_Click($null) } catch { }

    if ($RunButton) {
        $RunButton.Add_Click({
            # 1) Uninstall selected from Installed apps
            Invoke-QOTUninstallSelectedApps -Grid $AppsGrid

            # 2) Install selected from Common installs
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
