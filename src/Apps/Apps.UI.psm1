# Apps.UI.psm1
# UI logic for the Apps tab (scan, uninstall, install common apps)

param()

# Try to bring in logging + app logic
try {
    if (-not (Get-Command Write-QLog -ErrorAction SilentlyContinue)) {
        Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction SilentlyContinue
    }
} catch { }

Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force

# We also depend on the main window status helpers
try {
    Import-Module "$PSScriptRoot\..\UI\MainWindow.UI.psm1" -Force -ErrorAction SilentlyContinue
} catch { }

# Collections bound to the two DataGrids
if (-not $Global:QOT_InstalledAppsCollection) {
    $Global:QOT_InstalledAppsCollection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
}
if (-not $Global:QOT_CommonAppsCollection) {
    $Global:QOT_CommonAppsCollection    = New-Object System.Collections.ObjectModel.ObservableCollection[object]
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
        Write-QLog "Update-QOTStatusSafe error: $($_.Exception.Message)" "WARN"
    }
}

function Refresh-QOTInstalledAppsGrid {
    <#
        .SYNOPSIS
            Scans installed apps and repopulates the top grid.
    #>
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
            try {
                $row = [pscustomobject]@{
                    IsSelected    = $false
                    Name          = $app.Name
                    Publisher     = $app.Publisher
                    SizeMB        = $app.SizeMB
                    InstallDate   = $app.InstallDate
                    Risk          = $app.Risk
                    Uninstall     = $app.UninstallString
                    IsWhitelisted = $app.IsWhitelisted
                    IsSelectable  = -not $app.IsWhitelisted -and
                                    $app.Risk -ne "Red"       -and
                                    [bool]$app.UninstallString
                }

                $Global:QOT_InstalledAppsCollection.Add($row) | Out-Null
            } catch {
                Write-QLog "Apps tab: failed to add app row for '$($app.Name)': $($_.Exception.Message)" "WARN"
            }
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
        [System.Windows.MessageBox]::Show(
            "There was an error while scanning installed apps:`n`n$msg",
            "Quinn Optimiser Toolkit",
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Refresh-QOTCommonAppsGrid {
    <#
        .SYNOPSIS
            Loads the list of common apps and populates the bottom grid.
    #>
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
            # Make sure there is an IsSelected property even if the
            # underlying object doesn’t define one.
            if (-not ($app.PSObject.Properties.Name -contains "IsSelected")) {
                $app | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false
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
    <#
        .SYNOPSIS
            Uninstalls selected apps from the top grid.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    $chosen = $Global:QOT_InstalledAppsCollection | Where-Object { $_.IsSelected }

    if (-not $chosen) {
        [System.Windows.MessageBox]::Show(
            "No apps selected.",
            "Apps",
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    $protected = $chosen | Where-Object {
        $_.IsWhitelisted -or
        $_.Risk -eq "Red" -or
        -not $_.Uninstall
    }

    $toRemove = $chosen | Where-Object {
        -not ($_.IsWhitelisted -or $_.Risk -eq "Red" -or -not $_.Uninstall)
    }

    if (-not $toRemove) {
        [System.Windows.MessageBox]::Show(
            "All selected apps are on the protection whitelist or look like system components.`n`nNothing will be uninstalled.",
            "Apps",
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    if ($protected) {
        $protNames = ($protected.Name -join ", ")
        Write-QLog "Apps tab: protected apps skipped during uninstall: $protNames"
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

    $count    = $toRemove.Count
    if ($count -lt 1) { $count = 1 }
    $index    = 0
    $failures = @()

    foreach ($app in $toRemove) {
        $index++
        Update-QOTStatusSafe ("Uninstalling {0} ({1}/{2})" -f $app.Name, $index, $count)
        Write-QLog "Apps tab: attempting uninstall for $($app.Name)"

        try {
            $cmd  = $app.Uninstall
            if (-not $cmd) {
                Write-QLog "Apps tab: no UninstallString for $($app.Name); skipping." "WARN"
                $failures += $app.Name
                continue
            }

            $cmd  = $cmd.Trim()
            $exe  = $null
            $args = ""

            if ($cmd.StartsWith('"')) {
                $secondQuote = $cmd.IndexOf('"', 1)
                if ($secondQuote -gt 0) {
                    $exe  = $cmd.Substring(1, $secondQuote - 1)
                    $args = $cmd.Substring($secondQuote + 1).Trim()
                }
            }

            if (-not $exe) {
                $parts = $cmd.Split(" ", 2, [System.StringSplitOptions]::RemoveEmptyEntries)
                $exe   = $parts[0]
                if ($parts.Count -gt 1) { $args = $parts[1] }
            }

            if (-not (Test-Path $exe)) {
                Write-QLog "Apps tab: exe path '$exe' not found for $($app.Name). Running raw command via cmd." "WARN"
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -WindowStyle Hidden
            }
            elseif ($exe -match "msiexec\.exe") {
                if ($args -notmatch "/quiet" -and $args -notmatch "/qn") {
                    $args = "$args /quiet /norestart"
                }
                Start-Process -FilePath $exe -ArgumentList $args -Wait -WindowStyle Hidden
            }
            else {
                if ($args -notmatch "/S" -and
                    $args -notmatch "/silent" -and
                    $args -notmatch "/verysilent" -and
                    $args -notmatch "/quiet")
                {
                    $args = ($args + " /S").Trim()
                }

                Start-Process -FilePath $exe -ArgumentList $args -Wait -WindowStyle Hidden
            }

            Write-QLog "Apps tab: uninstall completed for $($app.Name)"
        }
        catch {
            $msg = $_.Exception.Message
            Write-QLog "Apps tab: uninstall failed for $($app.Name): $msg" "ERROR"
            $failures += $app.Name
        }
    }

    Refresh-QOTInstalledAppsGrid -Grid $Grid
    Update-QOTStatusSafe "Uninstall complete."

    if ($failures.Count -gt 0) {
        $failedNames = ($failures -join ", ")
        [System.Windows.MessageBox]::Show(
            "Some apps could not be uninstalled:`n`n$failedNames`n`nCheck the log for details.",
            "Apps",
            'OK',
            'Warning'
        ) | Out-Null
    }
}

function Initialize-QOTAppsUI {
    <#
        .SYNOPSIS
            Wires up the Apps tab controls.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$BtnScanApps,

        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$BtnUninstallSelected,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$AppsGrid,

        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$InstallGrid
    )

    # Bind collections
    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    # Rescan button
    $BtnScanApps.Add_Click({
        Refresh-QOTInstalledAppsGrid -Grid $AppsGrid
        Refresh-QOTCommonAppsGrid    -Grid $InstallGrid
    })

    # Uninstall selected button
    $BtnUninstallSelected.Add_Click({
        Invoke-QOTUninstallSelectedApps -Grid $AppsGrid
    })

    # Install button clicks inside the common apps grid
    $InstallGrid.AddHandler(
        [System.Windows.Controls.Button]::ClickEvent,
        [System.Windows.RoutedEventHandler]{
            param($sender, $e)

            $button = $e.OriginalSource
            if (-not ($button -is [System.Windows.Controls.Button])) { return }

            $row = $button.DataContext
            if (-not $row) { return }

            if (-not $row.IsInstallable) { return }

            $name = $row.Name
            $id   = $row.WingetId

            $confirm = [System.Windows.MessageBox]::Show(
                "Install $name from winget?",
                "Install app",
                'YesNo',
                'Question'
            )

            if ($confirm -ne 'Yes') { return }

            Update-QOTStatusSafe "Installing $name..."
            Install-QOTCommonApp -WingetId $id -Name $name | Out-Null

            # Refresh statuses so the row updates
            Refresh-QOTCommonAppsGrid -Grid $InstallGrid
            Update-QOTStatusSafe "Common apps list updated after install."
        }
    )

    # Initial load
    Refresh-QOTInstalledAppsGrid -Grid $AppsGrid
    Refresh-QOTCommonAppsGrid    -Grid $InstallGrid

    Write-QLog "Apps tab UI initialised."
}

Export-ModuleMember -Function `
    Refresh-QOTInstalledAppsGrid, `
    Refresh-QOTCommonAppsGrid, `
    Invoke-QOTUninstallSelectedApps, `
    Initialize-QOTAppsUI

