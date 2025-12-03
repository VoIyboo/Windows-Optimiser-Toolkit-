# src/Modules/Dashboard.psm1
# System health / dashboard logic for Quinn Optimiser Toolkit

# Requires: Logging.psm1 already imported (Write-QLog)

function Get-QCpuAndRamUsage {
    try {
        # CPU
        $cpuSample = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
        $cpu = [math]::Round($cpuSample.CounterSamples[0].CookedValue, 1)

        # RAM
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $totalMb = [math]::Round($os.TotalVisibleMemorySize / 1024, 1)
        $freeMb  = [math]::Round($os.FreePhysicalMemory / 1024, 1)
        $usedMb  = $totalMb - $freeMb
        $ramPct  = if ($totalMb -gt 0) { [math]::Round(($usedMb / $totalMb) * 100, 1) } else { 0 }

        return [pscustomobject]@{
            CpuPercent = $cpu
            RamPercent = $ramPct
            RamUsedMB  = $usedMb
            RamTotalMB = $totalMb
        }
    }
    catch {
        Write-QLog "Dashboard: failed to read CPU/RAM usage: $($_.Exception.Message)" "WARN"
        return [pscustomobject]@{
            CpuPercent = 0
            RamPercent = 0
            RamUsedMB  = 0
            RamTotalMB = 0
        }
    }
}

function Get-QDiskUsage {
    param(
        [string]$DriveName = 'C'
    )

    try {
        $drive = Get-PSDrive -Name $DriveName -ErrorAction Stop
        $usedGb  = [math]::Round($drive.Used / 1GB, 1)
        $freeGb  = [math]::Round($drive.Free / 1GB, 1)
        $totalGb = [math]::Round(($drive.Used + $drive.Free) / 1GB, 1)
        $freePct = if (($drive.Used + $drive.Free) -gt 0) {
            [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 1)
        } else { 0 }

        return [pscustomobject]@{
            Drive       = "$DriveName`:"
            UsedGB      = $usedGb
            FreeGB      = $freeGb
            TotalGB     = $totalGb
            FreePercent = $freePct
        }
    }
    catch {
        Write-QLog "Dashboard: failed to read disk usage for drive $DriveName`: $($_.Exception.Message)" "WARN"
        return [pscustomobject]@{
            Drive       = "$DriveName`:"
            UsedGB      = 0
            FreeGB      = 0
            TotalGB     = 0
            FreePercent = 0
        }
    }
}

function Get-QLargestFolders {
    param(
        [string]$Root = 'C:\',
        [int]$Top = 5
    )

    # Light-weight “good enough” scan: only direct subfolders of the root
    $results = @()

    try {
        $folders = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue
        foreach ($f in $folders) {
            try {
                $size = (Get-ChildItem -Path $f.FullName -Recurse -File -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum).Sum
                $sizeGb = [math]::Round(($size / 1GB), 2)
                $results += [pscustomobject]@{
                    Name   = $f.Name
                    Path   = $f.FullName
                    SizeGB = $sizeGb
                }
            }
            catch {
                # Ignore individual folder errors
                Write-QLog "Dashboard: failed to calculate size for folder $($f.FullName): $($_.Exception.Message)" "DEBUG"
            }
        }
    }
    catch {
        Write-QLog ("Dashboard: error while scanning folders under {0}: {1}" -f $folder.FullName, $_.Exception.Message) "WARN"
    }

    $results |
        Where-Object { $_.SizeGB -gt 0 } |
        Sort-Object SizeGB -Descending |
        Select-Object -First $Top
}

function Get-QLargestInstalledApps {
    param(
        [int]$Top = 5
    )

    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $apps = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $_.DisplayName) { return }

            # Skip pure system updates
            if ($_.ReleaseType -eq 'Security Update' -or $_.ParentKeyName) { return }

            $sizeMb = $null
            if ($_.EstimatedSize) { $sizeMb = [math]::Round($_.EstimatedSize / 1024, 1) }

            if ($sizeMb -and $sizeMb -gt 0) {
                [pscustomobject]@{
                    Name   = $_.DisplayName
                    Publisher = $_.Publisher
                    SizeMB = $sizeMb
                }
            }
        }
    }

    $apps |
        Sort-Object SizeMB -Descending |
        Select-Object -First $Top
}

function Get-QDashboardSummary {
    <#
        Returns a single object with everything the UI needs:
        - CPU / RAM
        - Disk usage (C:)
        - Largest folders on C:\
        - Largest installed apps
        - Simple health string + recommended actions text
    #>

    Write-QLog "Dashboard: starting system health scan."

    $cpuRam   = Get-QCpuAndRamUsage
    $disk     = Get-QDiskUsage -DriveName 'C'
    $folders  = Get-QLargestFolders -Root 'C:\' -Top 5
    $apps     = Get-QLargestInstalledApps -Top 5

    # Very simple health scoring
    $issues = @()

    if ($cpuRam.CpuPercent -gt 80) {
        $issues += "High CPU usage detected."
    }
    if ($cpuRam.RamPercent -gt 80) {
        $issues += "RAM usage is above 80%."
    }
    if ($disk.FreePercent -lt 15) {
        $issues += "Disk C: has less than 15% free space."
    }

    if (-not $issues) {
        $healthText = "Healthy"
    }
    else {
        $healthText = ($issues -join " ")
    }

    $recommended = @()
    if ($disk.FreePercent -lt 20) {
        $recommended += "Run disk cleanup to free space on C:."
    }
    if ($cpuRam.RamPercent -gt 80) {
        $recommended += "Close heavy apps or consider adding more RAM."
    }
    if (-not $recommended) {
        $recommended = @("No urgent actions detected. You can still run maintenance to keep things tidy.")
    }

    $summary = [pscustomobject]@{
        CpuRam        = $cpuRam
        Disk          = $disk
        LargestFolders = $folders
        LargestApps    = $apps
        HealthSummary  = $healthText
        RecommendedActions = $recommended
        ScanTime      = (Get-Date)
    }

    Write-QLog "Dashboard: system health scan finished."
    return $summary
}

Export-ModuleMember -Function Get-QDashboardSummary
