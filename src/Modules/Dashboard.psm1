# Dashboard.psm1
# System health + dashboard helpers for Quinn Optimiser Toolkit

# We assume Logging.psm1 has Write-QLog and Engine/Core has Set-QStatus available.

# ---------------------------
# UI wiring
# ---------------------------
function Hook-QDashboardUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    # Grab references to dashboard controls from XAML
    $Global:QOT_CpuRamValue        = $Window.FindName("CpuRamValueText")
    $Global:QOT_DiskUsageValue     = $Window.FindName("DiskUsageValueText")
    $Global:QOT_SystemHealthValue  = $Window.FindName("SystemHealthValueText")
    $Global:QOT_LargestFoldersList = $Window.FindName("LargestFoldersList")
    $Global:QOT_LargestAppsList    = $Window.FindName("LargestAppsList")
    $Global:QOT_RecommendButton    = $Window.FindName("BtnAnalyseSystem")

    Write-QLog "Dashboard UI hooked: CPU/RAM, disk, system health and lists."
}

# ---------------------------
# Core data helpers
# ---------------------------

function Get-QCpuRamSnapshot {
    [CmdletBinding()]
    param()

    try {
        # Quick CPU sample
        $cpuObj = Get-WmiObject -Class Win32_Processor -ErrorAction Stop
        $cpuAvg = ($cpuObj | Measure-Object -Property LoadPercentage -Average).Average

        # RAM from OS
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $total = [double]$os.TotalVisibleMemorySize
        $free  = [double]$os.FreePhysicalMemory
        $usedPct = [math]::Round((($total - $free) / $total) * 100, 0)

        [pscustomobject]@{
            CpuPercent = [int][math]::Round($cpuAvg, 0)
            RamPercent = [int]$usedPct
        }
    }
    catch {
        Write-QLog ("Dashboard: CPU/RAM snapshot failed: {0}" -f $_.Exception.Message) "WARN"
        [pscustomobject]@{
            CpuPercent = 0
            RamPercent = 0
        }
    }
}

function Get-QDiskUsageC {
    [CmdletBinding()]
    param()

    try {
        $drive = Get-PSDrive -Name C -ErrorAction Stop
        $usedGB  = [math]::Round($drive.Used  / 1GB, 1)
        $freeGB  = [math]::Round($drive.Free  / 1GB, 1)
        $totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 1)

        [pscustomobject]@{
            UsedGB  = $usedGB
            FreeGB  = $freeGB
            TotalGB = $totalGB
        }
    }
    catch {
        Write-QLog ("Dashboard: disk usage snapshot failed: {0}" -f $_.Exception.Message) "WARN"
        [pscustomobject]@{
            UsedGB  = 0
            FreeGB  = 0
            TotalGB = 0
        }
    }
}

function Get-QLargestFolders {
    [CmdletBinding()]
    param(
        [string]$Root = "C:\",
        [int]$Top = 10
    )

    $results = @()

    try {
        # Keep it reasonably fast: only top-level folders, shallow size calc
        $folders = Get-ChildItem -Path $Root -Directory -ErrorAction Stop

        foreach ($folder in $folders) {
            try {
                $sizeBytes = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
                              Measure-Object -Property Length -Sum).Sum
                if (-not $sizeBytes) { $sizeBytes = 0 }

                $results += [pscustomobject]@{
                    Name   = $folder.Name
                    Path   = $folder.FullName
                    SizeGB = [math]::Round($sizeBytes / 1GB, 2)
                }
            }
            catch {
                Write-QLog ("Dashboard: error while scanning folders under {0}: {1}" -f $folder.FullName, $_.Exception.Message) "WARN"
            }
        }
    }
    catch {
        Write-QLog ("Dashboard: top-level folder enumeration failed: {0}" -f $_.Exception.Message) "WARN"
    }

    $results |
        Where-Object { $_.SizeGB -gt 0 } |
        Sort-Object SizeGB -Descending |
        Select-Object -First $Top
}

# Placeholder – you can later swap this for a smarter app size scan
function Get-QLargestAppsPlaceholder {
    [CmdletBinding()]
    param(
        [int]$Top = 10
    )

    Write-QLog "Dashboard: using placeholder app list (hook into Apps module later)."

    1..$Top | ForEach-Object {
        [pscustomobject]@{
            Name   = "App $_ (placeholder)"
            SizeGB = 0
        }
    }
}

function Get-QSystemHealthSummary {
    param(
        [int]$CpuPercent,
        [int]$RamPercent,
        [double]$FreeDiskGB
    )

    if ($FreeDiskGB -lt 20) {
        return "Warning: low free space on C: (less than 20 GB)."
    }
    elseif ($RamPercent -gt 90) {
        return "Warning: RAM usage consistently high."
    }
    elseif ($CpuPercent -gt 90) {
        return "Warning: CPU under heavy load."
    }
    else {
        return "Overall system health looks OK."
    }
}

# ---------------------------
# Main dashboard scan
# ---------------------------
function Start-QDashboardScan {
    [CmdletBinding()]
    param()

    Write-QLog "Dashboard: starting system scan."
    try {
        Set-QStatus "Analysing system..." 0 $true
    }
    catch {
        # If Set-QStatus is not available yet, just ignore
    }

    $usage  = Get-QCpuRamSnapshot
    $disk   = Get-QDiskUsageC
    $health = Get-QSystemHealthSummary -CpuPercent $usage.CpuPercent -RamPercent $usage.RamPercent -FreeDiskGB $disk.FreeGB
    $folders = Get-QLargestFolders -Root "C:\" -Top 10
    $apps    = Get-QLargestAppsPlaceholder -Top 10

    # Update tiles
    if ($Global:QOT_CpuRamValue) {
        $Global:QOT_CpuRamValue.Text = ("CPU: {0}%    RAM: {1}%" -f $usage.CpuPercent, $usage.RamPercent)
    }

    if ($Global:QOT_DiskUsageValue) {
        $Global:QOT_DiskUsageValue.Text = ("{0} GB used / {1} GB free" -f $disk.UsedGB, $disk.FreeGB)
    }

    if ($Global:QOT_SystemHealthValue) {
        $Global:QOT_SystemHealthValue.Text = $health
    }

    # Update largest folders list
    if ($Global:QOT_LargestFoldersList) {
        $Global:QOT_LargestFoldersList.Items.Clear()
        foreach ($f in $folders) {
            $Global:QOT_LargestFoldersList.Items.Add(
                ("{0}  ({1} GB)" -f $f.Path, $f.SizeGB)
            ) | Out-Null
        }
    }

    # Placeholder largest apps list
    if ($Global:QOT_LargestAppsList) {
        $Global:QOT_LargestAppsList.Items.Clear()
        foreach ($a in $apps) {
            $Global:QOT_LargestAppsList.Items.Add(
                ("{0}  ({1} GB)" -f $a.Name, $a.SizeGB)
            ) | Out-Null
        }
    }

    try {
        Set-QStatus "Idle" 0 $false
    }
    catch { }

    Write-QLog "Dashboard: system scan completed."
}

Export-ModuleMember -Function `
    Hook-QDashboardUI, `
    Start-QDashboardScan, `
    Get-QCpuRamSnapshot, `
    Get-QDiskUsageC, `
    Get-QLargestFolders
