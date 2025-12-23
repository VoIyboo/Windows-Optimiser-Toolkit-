# src\Apps\Apps.UI.psm1
# UI wiring for the Apps tab
# Goals
# - No Scan apps button
# - No Uninstall selected button
# - Installed apps auto scan on load without freezing UI
# - Uninstall only when Run selected actions is clicked, based on checkboxes
# - Common app installs shows checkbox, name, version, and stays fast (static catalogue)
# - Common app installs only runs installs when Run selected actions is clicked

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

    # Hide old buttons (you can remove them from XAML later)
    if ($BtnScanApps) { $BtnScanApps.Visibility = 'Collapsed' }
    if ($BtnUninstallSelected) { $BtnUninstallSelected.Visibility = 'Collapsed' }

    # Ensure collections exist
    Initialize-QOTAppsCollections

    # Bind sources
    $AppsGrid.ItemsSource    = $Global:QOT_InstalledAppsCollection
    $InstallGrid.ItemsSource = $Global:QOT_CommonAppsCollection

    # Build stable columns (no AutoGenerate)
    Initialize-QOTAppsGridsColumns -AppsGrid $AppsGrid -InstallGrid $InstallGrid

    # Load common apps as a static catalogue (instant, no scanning)
    Initialize-QOTCommonAppsCatalogue

    # Auto scan installed apps without UI lag
    Start-QOTInstalledAppsScanAsync -AppsGrid $AppsGrid

    # Run selected actions becomes the one button to rule them all
    if ($RunButton) {
        $RunButton.Add_Click({
            try {
                Invoke-QOTUninstallSelectedApps -Grid $AppsGrid
            } catch {
                try { Write-QLog "Uninstall failed: $($_.Exception.Message)" "ERROR" } catch { }
            }

            try {
                Invoke-QOTInstallSelectedCommonApps -Grid $InstallGrid
            } catch {
                try { Write-QLog "Install failed: $($_.Exception.Message)" "ERROR" } catch { }
            }
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

function Initialize-QOTAppsGridsColumns {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$AppsGrid,
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$InstallGrid
    )

    # Installed Apps grid
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

    # Common Apps grid (static catalogue)
    $InstallGrid.AutoGenerateColumns = $false
    $InstallGrid.CanUserAddRows      = $false
    $InstallGrid.IsReadOnly          = $false
    $InstallGrid.Columns.Clear()

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridCheckBoxColumn -Property @{
        Header  = ""
        Binding = (New-Object System.Windows.Data.Binding "IsSelected")
        Width   = 40
    }))

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "App"
        Binding    = (New-Object System.Windows.Data.Binding "Name")
        Width      = "*"
        IsReadOnly = $true
    }))

    $InstallGrid.Columns.Add((New-Object System.Windows.Controls.DataGridTextColumn -Property @{
        Header     = "Version"
        Binding    = (New-Object System.Windows.Data.Binding "Version")
        Width      = 140
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

            # This must exist in your InstalledApps.psm1
            $e.Result = Get-QOTInstalledApps
        }

        $bw.RunWorkerCompleted += {
            param($sender, $e)

            try {
                if ($e.Error) {
                    try { Write-QLog "Installed apps scan failed: $($e.Error.Message)" "ERROR" } catch { }
                    return
                }

                $results = @($e.Result)

                $dispatcher.Invoke([action]{
                    $Global:QOT_InstalledAppsCollection.Clear()

                    foreach ($app in $results) {
                        Ensure-QOTAppObjectForGrid -App $app
                        $Global:QOT_InstalledAppsCollection.Add($app)
                    }
                })

                try { Write-QLog "Installed apps scan complete. Loaded $($results.Count) items." } catch { }
            }
            catch {
                try { Write-QLog "Installed apps scan post processing failed: $($_.Exception.Message)" "ERROR" } catch { }
            }
        }

        if (-not $bw.IsBusy) {
            try { Write-QLog "Starting installed apps scan (async)." } catch { }
            $bw.RunWorkerAsync() | Out-Null
        }
    }
    catch {
        try { Write-QLog "Start-QOTInstalledAppsScanAsync error: $($_.Exception.Message)" "ERROR" } catch { }
    }
}

function Ensure-QOTAppObjectForGrid {
    param(
        [Parameter(Mandatory)][object]$App
    )

    if ($null -eq $App.PSObject.Properties["IsSelected"]) {
        $App | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
    }

    # If your scanner already sets Version, great. If not, set empty to avoid binding errors.
    if ($null -eq $App.PSObject.Properties["Version"]) {
        $App | Add-Member -NotePropertyName Version -NotePropertyValue "" -Force
    }
}

function Initialize-QOTCommonAppsCatalogue {

    # Do not rebuild every time user visits the tab
    if ($Global:QOT_CommonAppsCollection.Count -gt 0) { return }

    # Static catalogue only, no scanning, no checking installed state
    # You can swap these IDs to match your preferred sources
    $catalogue = @(
        [pscustomobject]@{ IsSelected = $false; Name = "Google Chrome";         Version = "Latest"; Id = "Google.Chrome" },
        [pscustomobject]@{ IsSelected = $false; Name = "Microsoft Edge";        Version = "Latest"; Id = "Microsoft.Edge" },
        [pscustomobject]@{ IsSelected = $false; Name = "7 Zip";                Version = "Latest"; Id = "7zip.7zip" },
        [pscustomobject]@{ IsSelected = $false; Name = "Notepad++";            Version = "Latest"; Id = "Notepad++.Notepad++" },
        [pscustomobject]@{ IsSelected = $false; Name = "VLC";                  Version = "Latest"; Id = "VideoLAN.VLC" },
        [pscustomobject]@{ IsSelected = $false; Name = "Git";                  Version = "Latest"; Id = "Git.Git" },
        [pscustomobject]@{ IsSelected = $false; Name = "Visual Studio Code";   Version = "Latest"; Id = "Microsoft.VisualStudioCode" },
        [pscustomobject]@{ IsSelected = $false; Name = "Adobe Acrobat Reader"; Version = "Latest"; Id = "Adobe.Acrobat.Reader.64-bit" }
    )

    foreach ($item in $catalogue) {
        $Global:QOT_CommonAppsCollection.Add($item)
    }

    try { Write-QLog "Common apps catalogue initialised ($($Global:QOT_CommonAppsCollection.Count) apps)." } catch { }
}

function Invoke-QOTUninstallSelectedApps {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    $items = @($Grid.ItemsSource)
    if ($items.Count -eq 0) {
        try { Write-QLog "Uninstall skipped. No installed apps loaded." "WARN" } catch { }
        return
    }

    $selected = @($items | Where-Object { $_.IsSelected -eq $true })
    if ($selected.Count -eq 0) {
        try { Write-QLog "Uninstall skipped. No apps selected." } catch { }
        return
    }

    foreach ($app in $selected) {
        $name = $app.Name
        $cmd  = $app.UninstallString

        if ([string]::IsNullOrWhiteSpace($cmd)) {
            try { Write-QLog "Skipping uninstall for '$name' because UninstallString is empty." "WARN" } catch { }
            continue
        }

        try {
            Write-QLog "Uninstalling: $name"

            # Run via cmd to support most registry uninstall strings
            Start-QOTProcessFromCommand -Command $cmd -Wait

            $app.IsSelected = $false
        }
        catch {
            try { Write-QLog "Failed uninstall '$name': $($_.Exception.Message)" "ERROR" } catch { }
        }
    }
}

function Invoke-QOTInstallSelectedCommonApps {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid
    )

    $items = @($Grid.ItemsSource)
    if ($items.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps catalogue loaded." "WARN" } catch { }
        return
    }

    $selected = @($items | Where-Object { $_.IsSelected -eq $true })
    if ($selected.Count -eq 0) {
        try { Write-QLog "Install skipped. No common apps selected." } catch { }
        return
    }

    foreach ($app in $selected) {
        $name = $app.Name
        $id   = $app.Id

        if ([string]::IsNullOrWhiteSpace($id)) {
            try { Write-QLog "Skipping install for '$name' because Id is empty." "WARN" } catch { }
            continue
        }

        try {
            Write-QLog "Installing: $name ($id)"

            # Install only at runtime, keeps UI fast
            $args = @(
                "install",
                "--id", $id,
                "-e",
                "--silent",
                "--accept-source-agreements",
                "--accept-package-agreements"
            )

            Start-Process -FilePath "winget" -ArgumentList $args -Wait -WindowStyle Hidden

            $app.IsSelected = $false
        }
        catch {
            try { Write-QLog "Failed install '$name': $($_.Exception.Message)" "ERROR" } catch { }
        }
    }
}

function Start-QOTProcessFromCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$Wait
    )

    # Many uninstall strings are already full commands, quoted paths, or msiexec lines.
    # Running through cmd.exe /c is the most compatible default.
    $cmdArgs = @("/c", $Command)

    if ($Wait) {
        Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -Wait -WindowStyle Hidden
    } else {
        Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WindowStyle Hidden
    }
}

Export-ModuleMember -Function `
    Initialize-QOTAppsUI, `
    Initialize-QOTAppsCollections, `
    Initialize-QOTAppsGridsColumns, `
    Start-QOTInstalledAppsScanAsync, `
    Initialize-QOTCommonAppsCatalogue, `
    Invoke-QOTUninstallSelectedApps, `
    Invoke-QOTInstallSelectedCommonApps
