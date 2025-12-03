# Dashboard.psm1
# System health summary and dashboard wiring for Quinn Optimiser Toolkit

# --------- Helper: logging wrapper ----------
function Write-QDashLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    if (Get-Command -Name Write-QLog -ErrorAction SilentlyContinue) {
        Write-QLog $Message $Level
    }
}

# --------- Core summary function (fast) ----------
function Get-QDashboardSummary {
    Write-QDashLog "Dashboard: collecting quick system summary..."

    # CPU
    $cpuPercent = 0
    try {
        $cpuSample  = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
        $cpuPercent = [math]::Round($cpuSample.CounterSamples.CookedValue, 0)
    } catch {
        Write-QDashLog ("Dashboard: CPU read failed: {0}" -f $_.Exception.Message) "WARN"
    }

    # RAM
    $ramPercent = 0
    try {
        $os        = Get-CimInstance Win32_OperatingSystem
        $totalMB   = $os.TotalVisibleMemorySize
        $freeMB    = $os.FreePhysicalMemory
        if ($totalMB -gt 0) {
            $usedPct   = (1 - ($freeMB / $totalMB)) * 100
            $ramPercent = [math]::Round($usedPct, 0)
        }
    } catch {
        Write-QDashLog ("Dashboard: RAM read failed: {0}" -f $_.Exception.Message) "WARN"
    }

    # Disk C
    $diskUsedGB  = 0
    $diskFreeGB  = 0
    $diskTotalGB = 0
    try {
        $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        if ($drive) {
            $diskTotalGB = [math]::Round($drive.Size / 1GB, 1)
            $diskFreeGB  = [math]::Round($drive.FreeSpace / 1GB, 1)
            $diskUsedGB  = [math]::Round($diskTotalGB - $diskFreeGB, 1)
        }
    } catch {
        Write-QDashLog ("Dashboard: disk read failed: {0}" -f $_.Exception.Message) "WARN"
    }

    # Simple health text based on thresholds
    $health = "Healthy"
    if ($cpuPercent -ge 85 -or $ramPercent -ge 85) {
        $health = "Under load"
    }
    if ($diskTotalGB -gt 0 -and $diskFreeGB -lt ($diskTotalGB * 0.15)) {
        $health = "Low disk space"
    }

    # For now keep these light weight
    $largestFolders = @()
    $largestApps    = @()

    # Placeholders for maintenance data until the scheduler module is hooked in
    $lastMaintenance  = "Never run"
    $recommendedQuick = "Run a scan to get recommendations."

    [pscustomobject]@{
        CpuPercent          = $cpuPercent
        RamPercent          = $ramPercent
        DiskUsedGB          = $diskUsedGB
        DiskFreeGB          = $diskFreeGB
        DiskTotalGB         = $diskTotalGB
        SystemHealth        = $health
        LargestFolders      = $largestFolders
        LargestApps         = $largestApps
        LastMaintenance     = $lastMaintenance
        RecommendedActions  = $recommendedQuick
    }
}

# --------- Hook UI controls into globals ----------
function Hook-QDashboardUI {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Window]$Window
    )

    Write-QDashLog "Dashboard: hooking UI controls."

    $Global:QOT_DashCpuText          = $Window.FindName("CpuText")
    $Global:QOT_DashRamText          = $Window.FindName("RamText")
    $Global:QOT_DashDiskText         = $Window.FindName("DiskUsageText")
    $Global:QOT_DashHealthText       = $Window.FindName("HealthText")

    $Global:QOT_DashLargestFolderDG  = $Window.FindName("LargestFoldersGrid")
    $Global:QOT_DashLargestAppsDG    = $Window.FindName("LargestAppsGrid")

    $Global:QOT_DashLastMaintText    = $Window.FindName("LastMaintenanceText")
    $Global:QOT_DashQuickActionsText = $Window.FindName("QuickActionsText")

    $Global:QOT_RecommendButton      = $Window.FindName("RecommendButton")

    # In case names do not match yet
    if (-not $Global:QOT_DashCpuText)          { Write-QDashLog "Dashboard: CpuText not found in XAML." "WARN" }
    if (-not $Global:QOT_DashRamText)          { Write-QDashLog "Dashboard: RamText not found in XAML." "WARN" }
    if (-not $Global:QOT_DashDiskText)         { Write-QDashLog "Dashboard: DiskUsageText not found in XAML." "WARN" }
    if (-not $Global:QOT_DashHealthText)       { Write-QDashLog "Dashboard: HealthText not found in XAML." "WARN" }
    if (-not $Global:QOT_DashLargestFolderDG)  { Write-QDashLog "Dashboard: LargestFoldersGrid not found in XAML." "WARN" }
    if (-not $Global:QOT_DashLargestAppsDG)    { Write-QDashLog "Dashboard: LargestAppsGrid not found in XAML." "WARN" }
    if (-not $Global:QOT_DashLastMaintText)    { Write-QDashLog "Dashboard: LastMaintenanceText not found in XAML." "WARN" }
    if (-not $Global:QOT_DashQuickActionsText) { Write-QDashLog "Dashboard: QuickActionsText not found in XAML." "WARN" }
    if (-not $Global:QOT_RecommendButton)      { Write-QDashLog "Dashboard: RecommendButton not found in XAML." "WARN" }
}

# --------- Push summary into the UI ----------
function Update-QDashboardUI {
    param(
        [Parameter(Mandatory = $true)]
        $Summary
    )

    if (-not $Summary) {
        Write-QDashLog "Dashboard: Update-QDashboardUI called with null summary" "WARN"
        return
    }

    # CPU / RAM
    if ($Global:QOT_DashCpuText) {
        $Global:QOT_DashCpuText.Text = "CPU: {0}%" -f $Summary.CpuPercent
    }
    if ($Global:QOT_DashRamText) {
        $Global:QOT_DashRamText.Text = "RAM: {0}%" -f $Summary.RamPercent
    }

    # Disk
    if ($Global:QOT_DashDiskText) {
        $Global:QOT_DashDiskText.Text = "{0} GB used / {1} GB free" -f $Summary.DiskUsedGB, $Summary.DiskFreeGB
    }

    # Health
    if ($Global:QOT_DashHealthText) {
        $Global:QOT_DashHealthText.Text = $Summary.SystemHealth
    }

    # Maintenance text
    if ($Global:QOT_DashLastMaintText) {
        $Global:QOT_DashLastMaintText.Text = $Summary.LastMaintenance
    }
    if ($Global:QOT_DashQuickActionsText) {
        $Global:QOT_DashQuickActionsText.Text = $Summary.RecommendedActions
    }

    # Data grids (placeholders for now)
    if ($Global:QOT_DashLargestFolderDG) {
        $Global:QOT_DashLargestFolderDG.ItemsSource = $Summary.LargestFolders
        $Global:QOT_DashLargestFolderDG.Items.Refresh()
    }
    if ($Global:QOT_DashLargestAppsDG) {
        $Global:QOT_DashLargestAppsDG.ItemsSource = $Summary.LargestApps
        $Global:QOT_DashLargestAppsDG.Items.Refresh()
    }
}

# --------- Full scan entry point used by the button and auto load ----------
function Start-QDashboardScan {
    Write-QDashLog "Dashboard: scan started."
    if (Get-Command -Name Set-QStatus -ErrorAction SilentlyContinue) {
        Set-QStatus "Scanning system health..." 0 $true
    }

    try {
        $summary = Get-QDashboardSummary
        Update-QDashboardUI -Summary $summary
        Write-QDashLog "Dashboard: scan completed."
    } catch {
        Write-QDashLog ("Dashboard: scan error: {0}" -f $_.Exception.Message) "ERROR"
    } finally {
        if (Get-Command -Name Set-QStatus -ErrorAction SilentlyContinue) {
            Set-QStatus "Idle" 0 $false
        }
    }
}

Export-ModuleMember -Function `
    Get-QDashboardSummary, `
    Update-QDashboardUI, `
    Hook-QDashboardUI, `
    Start-QDashboardScan
