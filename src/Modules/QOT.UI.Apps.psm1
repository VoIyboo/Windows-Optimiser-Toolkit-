# QOT.UI.Apps.psm1
# UI logic for the Apps tab (scan, uninstall, install via winget)

function Test-AppInstalledWinget {
    param(
        [string]$Id
    )
    try {
        $result = winget list --id $Id --source winget 2>$null
        if ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape($Id)) {
            return $true
        }
    } catch {
        Write-Log "winget list failed for ${Id}: $($_.Exception.Message)" "WARN"
    }
    return $false
}

function Install-AppWithWinget {
    param(
        $AppRow,
        [System.Windows.Controls.DataGrid]$InstallGrid
    )

    if (-not $AppRow -or -not $AppRow.WingetId) { return }

    Write-Log "Requested install: $($AppRow.Name) [$($AppRow.WingetId)]"
    Set-Status "Installing $($AppRow.Name)..." 0 $true

    try {
        $AppRow.Status = "Installing..."
        $InstallGrid.Items.Refresh()

        $cmd = "winget install --id `"$($AppRow.WingetId)`" -h --accept-source-agreements --accept-package-agreements"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -WindowStyle Hidden

        # Update fields instantly for the UI
        $AppRow.Status         = "Installed this session"
        $AppRow.InstallLabel   = "Installed"
        $AppRow.IsInstallable  = $false
        $AppRow.InstallTooltip = "Already installed"

        Write-Log "Install completed: $($AppRow.Name)"

        # Refresh UI row (safe dispatcher call)
        $InstallGrid.Dispatcher.Invoke({
            $InstallGrid.Items.Refresh()
        })

    } catch {
        $AppRow.Status = "Install failed"
        Write-Log "Install failed for $($AppRow.Name): $($_.Exception.Message)" "ERROR"
    }

    $InstallGrid.Items.Refresh()
    Set-Status "Idle" 0 $false
}

function Initialise-InstallAppsList {
    param(
        [System.Collections.ObjectModel.ObservableCollection[object]]$Collection
    )

    $definitions = @(
        @{ Name = "Google Chrome";      WingetId = "Google.Chrome"              }
        @{ Name = "Mozilla Firefox";    WingetId = "Mozilla.Firefox"            }
        @{ Name = "7-Zip";              WingetId = "7zip.7zip"                  }
        @{ Name = "VLC Media Player";   WingetId = "VideoLAN.VLC"               }
        @{ Name = "Notepad++";          WingetId = "Notepad++.Notepad++"        }
        @{ Name = "Discord";            WingetId = "Discord.Discord"            }
        @{ Name = "Spotify";            WingetId = "Spotify.Spotify"            }
        @{ Name = "Visual Studio Code"; WingetId = "Microsoft.VisualStudioCode" }
    )

    $Collection.Clear()

    foreach ($def in $definitions) {
        $status = "Not installed"
        if (Test-AppInstalledWinget -Id $def.WingetId) {
            $status = "Installed"
        }

        $isInstalled  = ($status -eq "Installed")

        $obj = [pscustomobject]@{
            IsSelected      = $false
            Name            = $def.Name
            WingetId        = $def.WingetId
            Status          = $status

            # New fields used by the XAML bindings
            InstallLabel    = if ($isInstalled) { "Installed" } else { "Install" }
            IsInstallable   = -not $isInstalled
            InstallTooltip  = if ($isInstalled) { "Already installed" } else { "Click to install" }
        }

        $Collection.Add($obj) | Out-Null
    }

    Write-Log "Initialised InstallApps list with $($Collection.Count) entries."
}

function Install-SelectedCommonApps {
    param(
        [System.Collections.ObjectModel.ObservableCollection[object]]$Collection,
        [System.Windows.Controls.DataGrid]$Grid
    )

    # Find all ticked rows in the bottom grid
    $selected = $Collection | Where-Object { $_.IsSelected }

    if (-not $selected) {
        [System.Windows.MessageBox]::Show(
            "No apps ticked in the list.",
            "Install common apps",
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    $names = $selected.Name -join ", "
    $confirm = [System.Windows.MessageBox]::Show(
        "Install the following app(s)?`n`n$names",
        "Confirm install",
        'YesNo',
        'Question'
    )

    if ($confirm -ne 'Yes') { return }

    Set-Status "Installing selected apps..." 0 $true
    Write-Log "Starting bulk install for common apps: $names"

    foreach ($app in $selected) {
        Install-AppWithWinget -AppRow $app -InstallGrid $Grid
    }

    # Rebuild list so statuses reflect current state
    Initialise-InstallAppsList -Collection $Collection

    Set-Status "Idle" 0 $false
}

function Refresh-InstalledApps {
    param(
        [System.Windows.Controls.DataGrid]$AppsGrid
    )

    Set-Status "Scanning apps..." 0 $true
    $Global:AppsCollection.Clear()
    Write-Log "Started scan for installed apps."

    try {
        $apps = Get-InstalledApps

        foreach ($a in $apps) {
            try {
                $risk = Get-AppRisk -App $a
                $obj = [pscustomobject]@{
                    IsSelected    = $false
                    IsSelectable  = -not $a.IsWhitelisted -and $risk -ne "Red"
                    Name          = $a.Name
                    Publisher     = $a.Publisher
                    SizeMB        = $a.SizeMB
                    InstallDate   = $a.InstallDate
                    Risk          = $risk
                    Uninstall     = $a.UninstallString
                    IsWhitelisted = $a.IsWhitelisted
                }
                $Global:AppsCollection.Add($obj) | Out-Null
            } catch {
                Write-Log "Failed to add app row for '$($a.Name)': $($_.Exception.Message)" "WARN"
            }
        }

        if ($AppsGrid) {
            $AppsGrid.Items.Refresh()
        }
        Write-Log "Finished scan for installed apps. Count: $($Global:AppsCollection.Count)"
        Set-Status "Idle" 0 $false
    } catch {
        Write-Log "Error in Refresh-InstalledApps: $($_.Exception.Message)" "ERROR"
        Set-Status "Error scanning apps" 0 $false
        [System.Windows.MessageBox]::Show(
            "There was an error while scanning apps:`n`n$($_.Exception.Message)`n`n" +
            "Check the log at $LogFile for more details.",
            "Quinn Optimiser Toolkit",
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Initialize-QOTAppsUI {
    param(
        [System.Windows.Controls.Button]$BtnScanApps,
        [System.Windows.Controls.Button]$BtnUninstallSelected,
        [System.Windows.Controls.DataGrid]$AppsGrid,
        [System.Windows.Controls.DataGrid]$InstallGrid
    )

    # Rescan button
    $BtnScanApps.Add_Click({
        Refresh-InstalledApps -AppsGrid $AppsGrid
        Initialise-InstallAppsList -Collection $Global:InstallAppsCollection
    })

    # Uninstall selected (with whitelist + refresh + logging)
    $BtnUninstallSelected.Add_Click({
        $chosen = $Global:AppsCollection | Where-Object { $_.IsSelected }

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
                "All selected apps are on the protection whitelist or are system components.`n`nNothing will be uninstalled.",
                "Apps",
                'OK',
                'Information'
            ) | Out-Null
            return
        }

        if ($protected) {
            $protNames = ($protected.Name -join ", ")
            Write-Log "Protected apps in selection (skipped): $protNames"
        }

        $names = ($toRemove.Name -join ", ")

        $confirm = [System.Windows.MessageBox]::Show(
            "Uninstall the following apps?`n`n$names",
            "Confirm uninstall",
            'YesNo',
            'Warning'
        )
        if ($confirm -ne 'Yes') { return }

        Set-Status "Uninstalling selected apps..." 0 $true
        Write-Log "Starting uninstall of selected apps: $names"

        $count = $toRemove.Count
        if ($count -lt 1) { $count = 1 }
        $i = 0
        $failures = @()

        foreach ($app in $toRemove) {
            $i++
            $pct = [int](($i / $count) * 100)
            Set-Status ("Uninstalling {0} ({1}/{2})" -f $app.Name, $i, $count) $pct $true
            Write-Log "Attempting uninstall: $($app.Name)"

            try {
                $cmd = $app.Uninstall
                if (-not $cmd) {
                    Write-Log "No UninstallString for $($app.Name), skipping." "WARN"
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
                    Write-Log "Exe path '$exe' not found for $($app.Name), running raw command via cmd." "WARN"
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

                Write-Log "Uninstall completed for $($app.Name)"
            }
            catch {
                $msg = $_.Exception.Message
                Write-Log "Uninstall failed for $($app.Name): $msg" "ERROR"
                $failures += $app.Name
            }
        }

        Refresh-InstalledApps -AppsGrid $AppsGrid
        Initialise-InstallAppsList -Collection $Global:InstallAppsCollection

        Set-Status "Idle" 0 $false

        if ($failures.Count -gt 0) {
            $failedNames = ($failures -join ", ")
            [System.Windows.MessageBox]::Show(
                "Some apps could not be uninstalled:`n`n$failedNames`n`nCheck the log at $LogFile for details.",
                "Apps",
                'OK',
                'Warning'
            ) | Out-Null
        }
    })

    # Install grid: per-row Install button with bulk support
    $InstallGrid.AddHandler(
        [System.Windows.Controls.Button]::ClickEvent,
        [System.Windows.RoutedEventHandler] {
            param($sender, $e)

            $button = $e.OriginalSource
            if (-not ($button -is [System.Windows.Controls.Button])) { return }

            $row = $button.DataContext
            if (-not $row) { return }

            $ticked = $Global:InstallAppsCollection | Where-Object { $_.IsSelected }

            if ($ticked -and $ticked.Count -gt 0) {
                if (-not $row.IsSelected) {
                    $row.IsSelected = $true
                }

                Install-SelectedCommonApps -Collection $Global:InstallAppsCollection -Grid $InstallGrid
            }
            else {
                Install-AppWithWinget -AppRow $row -InstallGrid $InstallGrid
                Initialise-InstallAppsList -Collection $Global:InstallAppsCollection
            }
        }
    )

    # Initial state
    Initialise-InstallAppsList -Collection $Global:InstallAppsCollection
}

Export-ModuleMember -Function Test-AppInstalledWinget, Install-AppWithWinget, `
    Initialise-InstallAppsList, Install-SelectedCommonApps, Refresh-InstalledApps, `
    Initialize-QOTAppsUI
