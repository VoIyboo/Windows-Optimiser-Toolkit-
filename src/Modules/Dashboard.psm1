# Dashboard.psm1
# System health summary + Dashboard tab wiring for Quinn Optimiser Toolkit

# --------------------------------------------------------------------
# Safe logging helper (uses core Write-QLog if available)
# --------------------------------------------------------------------
if (-not (Get-Command -Name Write-QLog -ErrorAction SilentlyContinue)) {
    function Write-QLog {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )
        # Fallback: no-op if logging module isn't loaded yet
    }
}

# --------------------------------------------------------------------
# Module-scope references to WPF controls
# --------------------------------------------------------------------
$script:CpuRamText        = $null
$script:DiskUsageText     = $null
$script:SystemHealthText  = $null
$script:FoldersList       = $null
$script:AppsList          = $null
$script:LastMaintText     = $null
$script:QuickActionsText  = $null

# --------------------------------------------------------------------
# Core: collect system summary
# --------------------------------------------------------------------
function Get-QDashboardSummary {
    [CmdletBinding()]
    param(
        [string]$DriveLetter = "C",
        [int]   $TopFolders  = 6,
        [int]   $TopApps     = 6
    )

    Write-QLog "Dashboard: collecting system summary..." "INFO"

    $summary = [ordered]@{
        CpuPercent                = $null
        RamPercent                = $null
        DiskUsedGB                = $null
        DiskFreeGB                = $null
        DiskTotalGB               = $null
        LargestFolders            = @()
        LargestApps               = @()
        SystemHealth              = "Unknown"
        LastMaintenance           = "Never run"
        RecommendedQuickActions   = @()
    }

    # ---- CPU --------------------------------------------------------
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $summary.CpuPercent = [math]::Round(
            ($cpu | Measure-Object -Property LoadPercentage -Average).Average,
            0
        )
    } catch {
        Write-QLog ("Dashboard: failed to read CPU load: {0}" -f $_.Exception.Message) "WARN"
    }

    # ---- RAM --------------------------------------------------------
    try {
        $os       = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalGB  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)  # KB -> GB
        $freeGB   = [math]::Round($os.FreePhysicalMemory / 1MB, 1)

        if ($totalGB -gt 0) {
            $usedPct            = [math]::Round((($totalGB - $freeGB) / $totalGB) * 100, 0)
            $summary.RamPercent = $usedPct
        }
    } catch {
        Write-QLog ("Dashboard: failed to read RAM: {0}" -f $_.Exception.Message) "WARN"
    }

    # ---- Disk (C:) --------------------------------------------------
    try {
        $drive    = Get-PSDrive -Name $DriveLetter -ErrorAction Stop
        $usedGB   = [math]::Round($drive.Used / 1GB, 1)
        $freeGB   = [math]::Round($drive.Free / 1GB, 1)
        $totalGB  = [math]::Round(($drive.Used + $drive.Free) / 1GB, 1)

        $summary.DiskUsedGB  = $usedGB
        $summary.DiskFreeGB  = $freeGB
        $summary.DiskTotalGB = $totalGB
    } catch {
        Write-QLog ("Dashboard: failed to read drive {0}: {1}" -f $DriveLetter, $_.Exception.Message) "WARN"
    }

    # ---- Simple health rating --------------------------------------
    if ($summary.DiskFreeGB -ne $null -and $summary.DiskFreeGB -lt 10) {
        $summary.SystemHealth = "Low disk space"
        $summary.RecommendedQuickActions += "Clean temp files and update cache."
    }
    elseif ($summary.RamPercent -ne $null -and $summary.RamPercent -gt 85) {
        $summary.SystemHealth = "High memory usage"
        $summary.RecommendedQuickActions += "Close unused apps or add more RAM."
    }
    else {
        $summary.SystemHealth = "Healthy"
    }

    # ---- Largest folders (lightweight scan) ------------------------
    try {
        $root = "$DriveLetter`:\"
        $topRoots = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                    Select-Object -First 10

        $largest = @()

        foreach ($folder in $topRoots) {
            try {
                $sizeBytes = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
                              Measure-Object -Property Length -Sum).Sum

                $sizeGB = if ($sizeBytes) { [math]::Round($sizeBytes / 1GB, 2) } else { 0 }

                $largest += [pscustomobject]@{
                    Name   = $folder.Name
                    Path   = $folder.FullName
                    SizeGB = $sizeGB
                }
            } catch {
                Write-QLog ("Dashboard: error while scanning folder {0}: {1}" -f $folder.FullName, $_.Exception.Message) "WARN"
            }
        }

        $summary.LargestFolders = $largest |
            Where-Object { $_.SizeGB -gt 0 } |
            Sort-Object SizeGB -Descending |
            Select-Object -First $TopFolders
    } catch {
        Write-QLog ("Dashboard: folder scan failed: {0}" -f $_.Exception.Message) "WARN"
    }

    # ---- Largest apps (if Apps module exposes inventory) -----------
    if (Get-Command -Name Get-QInstalledApps -ErrorAction SilentlyContinue) {
        try {
            $apps = Get-QInstalledApps
            $summary.LargestApps = $apps |
                Where-Object { $_.SizeMB -gt 0 } |
                Sort-Object SizeMB -Descending |
                Select-Object -First $TopApps
        } catch {
            Write-QLog ("Dashboard: failed to read installed apps: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    [pscustomobject]$summary
}

# --------------------------------------------------------------------
# Hook dashboard WPF controls
# --------------------------------------------------------------------
function Hook-QDashboardUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    # These names must match the x:Name values in MainWindow.xaml
    $script:CpuRamText        = $Window.FindName("CpuRamText")
    $script:DiskUsageText     = $Window.FindName("DiskUsageText")
    $script:SystemHealthText  = $Window.FindName("SystemHealthText")
    $script:FoldersList       = $Window.FindName("LargestFoldersList")
    $script:AppsList          = $Window.FindName("LargestAppsList")
    $script:LastMaintText     = $Window.FindName("LastMaintenanceText")
    $script:QuickActionsText  = $Window.FindName("QuickActionsText")

    Write-QLog "Dashboard: UI controls hooked." "INFO"
}

# --------------------------------------------------------------------
# Push summary into the UI
# --------------------------------------------------------------------
function Update-QDashboardUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Summary
    )

    if ($script:CpuRamText -and
        $Summary.CpuPercent -ne $null -and
        $Summary.RamPercent -ne $null) {

        $script:CpuRamText.Text = "CPU: {0}%   RAM: {1}%" -f $Summary.CpuPercent, $Summary.RamPercent
    }

    if ($script:DiskUsageText -and $Summary.DiskUsedGB -ne $null) {
        $script:DiskUsageText.Text = "{0} GB used / {1} GB free (of {2} GB)" -f `
            $Summary.DiskUsedGB, $Summary.DiskFreeGB, $Summary.DiskTotalGB
    }

    if ($script:SystemHealthText -and $Summary.SystemHealth) {
        $script:SystemHealthText.Text = $Summary.SystemHealth
    }

    if ($script:FoldersList) {
        $script:FoldersList.ItemsSource = $Summary.LargestFolders
    }

    if ($script:AppsList) {
        $script:AppsList.ItemsSource = $Summary.LargestApps
    }

    if ($script:LastMaintText -and $Summary.LastMaintenance) {
        $script:LastMaintText.Text = $Summary.LastMaintenance
    }

    if ($script:QuickActionsText) {
        if ($Summary.RecommendedQuickActions -and $Summary.RecommendedQuickActions.Count -gt 0) {
            $script:QuickActionsText.Text = ($Summary.RecommendedQuickActions -join "`r`n")
        } else {
            $script:QuickActionsText.Text = "No urgent actions detected. You can still run a cleanup from Tweaks & Cleaning."
        }
    }
}

# --------------------------------------------------------------------
# Entry point for scans (used by window Loaded + button)
# --------------------------------------------------------------------
function Start-QDashboardScan {
    Set-QStatus "Scanning system health..." 0 $true

    try {
        $summary = Get-QDashboardSummary
        Update-QDashboardUI -Summary $summary
    } catch {
        Write-QLog ("Dashboard: fatal error in Start-QDashboardScan: {0}" -f $_.Exception.Message) "ERROR"
    } finally {
        Set-QStatus "Idle" 0 $false
    }
}

Export-ModuleMember -Function `
    Get-QDashboardSummary, `
    Hook-QDashboardUI, `
    Update-QDashboardUI, `
    Start-QDashboardScan
