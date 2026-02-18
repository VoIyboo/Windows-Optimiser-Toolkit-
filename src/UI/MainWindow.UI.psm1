# src\UI\MainWindow.UI.psm1
# WPF main window loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# One time init for Tickets UI
$script:TicketsUIInitialised = $false
$script:AppsUIInitialised = $false
$script:MainWindow = $null
$script:SummaryTextBlock = $null
$script:SummaryTimer = $null
$script:PlayButtonTimer = $null
$script:IsPlayRunning = $false

function Write-QOTStartupTrace {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    $line = "[STARTUP] $Message"

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $line $Level
            return
        }
    } catch { }

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $consoleLine = "[$ts] $line"
    try { Write-Host $consoleLine } catch { }
}

function Get-QOTExceptionReport {
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $current = $Exception

    while ($current) {
        $parts.Add(("Exception[{0}] Type: {1}" -f $depth, $current.GetType().FullName))
        $parts.Add(("Exception[{0}] Message: {1}" -f $depth, $current.Message))
        if (-not [string]::IsNullOrWhiteSpace($current.StackTrace)) {
            $parts.Add(("Exception[{0}] StackTrace:`n{1}" -f $depth, $current.StackTrace))
        }

        $current = $current.InnerException
        $depth++
    }

    return ($parts -join [Environment]::NewLine)
}

function Invoke-QOTStartupStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$WarnThresholdMs = 200
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-QOTStartupTrace "$Name start"
    try {
        & $Action
    }
    catch {
        $sw.Stop()
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("{0} failed ({1} ms)`n{2}" -f $Name, [math]::Round($sw.Elapsed.TotalMilliseconds), $errorDetail) 'ERROR'
        throw
    }
    $sw.Stop()

    $durationMs = [math]::Round($sw.Elapsed.TotalMilliseconds)
    $level = if ($durationMs -ge $WarnThresholdMs) { 'WARN' } else { 'INFO' }
    Write-QOTStartupTrace ("{0} end ({1} ms)" -f $Name, $durationMs) $level
}

function Import-QOTModuleIfNeeded {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Global,
        [switch]$Optional
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        if ($Optional) { return }
        throw "Module path not found: $resolvedPath"
    }

    $alreadyLoaded = Get-Module | Where-Object { $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -eq $resolvedPath) }
    if ($alreadyLoaded) {
        Write-QOTStartupTrace ("Module already loaded: {0}" -f (Split-Path -Leaf $resolvedPath)) 'DEBUG'
        return
    }

    if ($Global) {
        Import-Module $resolvedPath -Global -ErrorAction Stop
    } else {
        Import-Module $resolvedPath -ErrorAction Stop
    }
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity) { return $false }

        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-QOTDriveSummary {
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    if (-not $drives) { return "n/a" }

    $segments = foreach ($drive in $drives) {
        if (-not $drive.Size -or $drive.Size -eq 0) { continue }
        $totalGB = [math]::Round($drive.Size / 1GB, 1)
        $freeGB = [math]::Round($drive.FreeSpace / 1GB, 1)
        $freePct = [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 0)
        "{0}: {1}/{2} GB free ({3}% free)" -f $drive.DeviceID, $freeGB, $totalGB, $freePct
    }

    if (-not $segments) { return "n/a" }
    return ($segments -join ", ")
}

function Get-QOTCpuSummary {
    $cpus = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
    if (-not $cpus) { return "n/a" }
    $avg = ($cpus | Measure-Object -Property LoadPercentage -Average).Average
    if ($null -eq $avg) { return "n/a" }
    return ("{0}%" -f [math]::Round($avg, 0))
}

function Get-QOTRamSummary {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os -or -not $os.TotalVisibleMemorySize) { return "n/a" }
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $freePct = if ($totalGB -gt 0) { [math]::Round(($freeGB / $totalGB) * 100, 0) } else { 0 }
    return ("{0}/{1} GB free ({2}% free)" -f $freeGB, $totalGB, $freePct)
}

function Get-QOTNetworkSummary {
    $adapters = Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue
    if (-not $adapters) { return "n/a" }
    $bytesPerSec = ($adapters | Measure-Object -Property BytesTotalPersec -Sum).Sum
    if ($null -eq $bytesPerSec) { return "n/a" }
    $mbps = [math]::Round(($bytesPerSec * 8) / 1MB, 1)
    return ("{0} Mbps" -f $mbps)
}

function Get-QOTGpuSummary {
    $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name -Unique
    if (-not $gpus) { return $null }
    return ($gpus -join ", ")
}

function Get-QOTSystemSummaryText {
    $parts = New-Object System.Collections.Generic.List[string]

    $parts.Add(("Drives: {0}" -f (Get-QOTDriveSummary)))
    $parts.Add(("CPU: {0}" -f (Get-QOTCpuSummary)))
    $parts.Add(("RAM: {0}" -f (Get-QOTRamSummary)))
    $parts.Add(("Network: {0}" -f (Get-QOTNetworkSummary)))

    $gpuSummary = Get-QOTGpuSummary
    if (-not [string]::IsNullOrWhiteSpace($gpuSummary)) {
        $parts.Add(("GPU: {0}" -f $gpuSummary))
    }

    return ($parts -join " | ")
}

function Set-QOTSummary {
    param(
        [string]$Text
    )

    if (-not $script:SummaryTextBlock) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $script:SummaryTextBlock.Text = $Text
}

function Set-QOTPlayProgress {
    param(
        [System.Windows.Shapes.Path]$ProgressPath,
        [System.Windows.Media.RectangleGeometry]$ProgressClip,
        [double]$Percent
    )

    if (-not $ProgressPath -or -not $ProgressClip) { return }
    $safePercent = [math]::Max(0, [math]::Min(100, $Percent))
    $height = 16.0
    $filled = ($height * $safePercent / 100.0)
    $top = $height - $filled
    $ProgressClip.Rect = New-Object System.Windows.Rect(0, $top, 16, $filled)
}

function Set-QOTUIEnabledState {
    param(
        [AllowNull()]
        $Control,
        [Parameter(Mandatory)][bool]$IsEnabled
    )

    if (-not $Control) { return $false }

    $hasIsEnabled = $null -ne $Control.PSObject.Properties['IsEnabled']
    if (-not $hasIsEnabled) {
        try { Write-QLog ("Skipping IsEnabled set; control type does not expose IsEnabled: {0}" -f $Control.GetType().FullName) "WARN" } catch { }
        return $false
    }

    $Control.IsEnabled = $IsEnabled
    return $true
}

function Set-QOTHitTestVisibility {
    param(
        [AllowNull()]
        $Control,
        [Parameter(Mandatory)][bool]$IsHitTestVisible
    )

    if (-not $Control) { return $false }

    $hasIsHitTestVisible = $null -ne $Control.PSObject.Properties['IsHitTestVisible']
    if (-not $hasIsHitTestVisible) {
        try { Write-QLog ("Skipping IsHitTestVisible set; control type does not expose IsHitTestVisible: {0}" -f $Control.GetType().FullName) "WARN" } catch { }
        return $false
    }

    $Control.IsHitTestVisible = $IsHitTestVisible
    return $true
}

function Invoke-QOTPlayCompletionSound {
    try {
        [console]::Beep(880, 120)
        [console]::Beep(1245, 140)
    }
    catch {
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
    }
}

function Resolve-QOTControlSet {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string[]]$Names
    )

    $resolved = @{}
    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($name in $Names) {
        $control = Find-QOTControlByNameDeep -Root $Root -Name $name
        if ($control) {
            $resolved[$name] = $control
        }
        else {
            $missing.Add($name) | Out-Null
        }
    }

    return [pscustomobject]@{
        Resolved = $resolved
        Missing  = @($missing)
    }
}

function Resolve-QOTControlSetFallback {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string[]]$Names
    )

    $resolved = @{}
    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($name in $Names) {
        $control = Find-QOTControlByNameDeep -Root $Root -Name $name
        if ($control) {
            $resolved[$name] = $control
        }
        else {
            $missing.Add($name) | Out-Null
        }
    }

    return [pscustomobject]@{
        Resolved = $resolved
        Missing  = @($missing)
    }
}

function Invoke-QOTControlResolution {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string[]]$Names
    )

    if (-not $Root) {
        throw "Invoke-QOTControlResolution requires a non-null root."
    }

    if ($script:MainWindow -and ([object]::ReferenceEquals($Root, $script:MainWindow) -eq $false)) {
        Write-QOTStartupTrace "Control resolution root does not match script:MainWindow; forcing resolver root to script:MainWindow" 'WARN'
        $Root = $script:MainWindow
    }

    try {
        return Resolve-QOTControlSet -Root $Root -Names $Names
    }
    catch {
        $errorText = "Resolve-QOTControlSet failed; falling back to legacy control resolution. Error: $($_.Exception.Message)"
        Write-QOTStartupTrace $errorText 'ERROR'
        try { Write-QLog $errorText 'ERROR' } catch { }
    }

    return Resolve-QOTControlSetFallback -Root $Root -Names $Names
}

function Run-QOTSelectedTasks {
    param(
        $Window,
        [System.Windows.Shapes.Path]$ProgressPath,
        [System.Windows.Media.RectangleGeometry]$ProgressClip
    )

    $activeWindow = $Window
    if (-not $activeWindow) {
        $activeWindow = $script:MainWindow
    }
    if (-not $activeWindow) {
        throw "Main window is not initialised. Cannot run selected tasks."
    }

    $scriptsRoot = Join-Path (Join-Path $PSScriptRoot "..") "Scripts"

    $checkboxActionMap = @{
        "Invoke-QCleanTemp" = @{ Name = "Clear temporary files"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanTemp.ps1" }
        "Invoke-QCleanRecycleBin" = @{ Name = "Empty Recycle Bin"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanRecycleBin.ps1" }
        "Invoke-QCleanDOCache" = @{ Name = "Clean Delivery Optimisation cache"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanDOCache.ps1" }
        "Invoke-QCleanWindowsUpdateCache" = @{ Name = "Clear Windows Update cache"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanWindowsUpdateCache.ps1" }
        "Invoke-QCleanThumbnailCache" = @{ Name = "Clean thumbnail cache"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanThumbnailCache.ps1" }
        "Invoke-QCleanErrorLogs" = @{ Name = "Clean old error logs and crash dumps"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanErrorLogs.ps1" }
        "Invoke-QCleanSetupLeftovers" = @{ Name = "Remove safe setup / upgrade leftovers"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanSetupLeftovers.ps1" }
        "Invoke-QCleanStoreCache" = @{ Name = "Clear Microsoft Store cache"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanStoreCache.ps1" }
        "Invoke-QCleanEdgeCache" = @{ Name = "Light clean of Microsoft Edge cache"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanEdgeCache.ps1" }
        "Invoke-QCleanChromeCache" = @{ Name = "Light clean of Chrome / Chromium cache"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanChromeCache.ps1" }
        "Invoke-QCleanDirectXShaderCache" = @{ Name = "Clear DirectX shader cache"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanDirectXShaderCache.ps1" }
        "Invoke-QCleanWERQueue" = @{ Name = "Clear Windows Error Reporting queue"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanWERQueue.ps1" }
        "Invoke-QCleanClipboardHistory" = @{ Name = "Clear clipboard history"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanClipboardHistory.ps1" }
        "Invoke-QCleanExplorerRecentItems" = @{ Name = "Clear Explorer Recent items and Jump Lists"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanExplorerRecentItems.ps1" }
        "Invoke-QCleanWindowsSearchHistory" = @{ Name = "Clear Windows Search history"; ScriptPath = Join-Path $scriptsRoot "Cleanup\Invoke-QCleanWindowsSearchHistory.ps1" }
        "Invoke-QTweakStartMenuRecommendations" = @{ Name = "Hide Start menu recommended items"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakStartMenuRecommendations.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakSuggestedApps" = @{ Name = "Turn off suggested apps and promotions"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakSuggestedApps.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakTipsInStart" = @{ Name = "Disable tips and suggestions in Start"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakTipsInStart.ps1" }
        "Invoke-QTweakBingSearch" = @{ Name = "Turn off Bing / web results in Start search"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakBingSearch.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakClassicContextMenu" = @{ Name = "Use classic 'More options' right-click menu"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakClassicContextMenu.ps1" }
        "Invoke-QTweakWidgets" = @{ Name = "Turn off Widgets"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakWidgets.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakNewsAndInterests" = @{ Name = "Turn off News / taskbar content"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakNewsAndInterests.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakMeetNow" = @{ Name = "Hide legacy Meet Now button"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakMeetNow.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakAdvertisingId" = @{ Name = "Turn off advertising ID"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakAdvertisingId.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakFeedbackHub" = @{ Name = "Reduce feedback and survey prompts"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakFeedbackHub.ps1"; RequiresAdmin = $true }
        "Invoke-QTweakOnlineTips" = @{ Name = "Disable online tips and suggestions"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakOnlineTips.ps1" }
        "Invoke-QTweakDisableLockScreenTips" = @{ Name = "Disable lock screen tips, suggestions, and spotlight extras"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakDisableLockScreenTips.ps1" }
        "Invoke-QTweakDisableSettingsSuggestedContent" = @{ Name = "Disable Suggested content in Settings"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakDisableSettingsSuggestedContent.ps1" }
        "Invoke-QTweakDisableTransparencyEffects" = @{ Name = "Turn off transparency effects"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakDisableTransparencyEffects.ps1" }
        "Invoke-QTweakDisableStartupDelay" = @{ Name = "Disable startup delay for startup apps"; ScriptPath = Join-Path $scriptsRoot "Tweaks\Invoke-QTweakDisableStartupDelay.ps1" }
    }

    $tabCleaning = $activeWindow.FindName("TabCleaning")
    $tweaksRoot = if ($tabCleaning -and $tabCleaning.Content) { $tabCleaning.Content } else { $tabCleaning }

    $selectedTasks = New-Object System.Collections.Generic.List[object]
    $discoveredCheckboxes = 0

    if ($tweaksRoot) {
        $q = New-Object 'System.Collections.Generic.Queue[System.Windows.DependencyObject]'
        $q.Enqueue($tweaksRoot) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()

            if ($cur -is [System.Windows.Controls.CheckBox]) {
                $actionId = [string]$cur.Tag
                if (-not [string]::IsNullOrWhiteSpace($actionId) -and $checkboxActionMap.ContainsKey($actionId)) {
                    $discoveredCheckboxes++
                    if ($cur.IsChecked -eq $true) {
                        $selectedTasks.Add($checkboxActionMap[$actionId]) | Out-Null
                    }
                }
            }

            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    }

    try { Write-QLog ("Tweaks & Cleaning checkboxes discovered in Play handler: {0}" -f $discoveredCheckboxes) "INFO" } catch { }

    $appsGrid = $activeWindow.FindName("AppsGrid")
    $installGrid = $activeWindow.FindName("InstallGrid")
    $appsSelectedCount = 0
    if ($appsGrid) {
        $appsSelectedCount += @(@($appsGrid.ItemsSource) | Where-Object { $_.IsSelected -eq $true }).Count
    }
    if ($installGrid) {
        $appsSelectedCount += @(@($installGrid.ItemsSource) | Where-Object { $_.IsSelected -eq $true -and $_.IsInstallable -ne $false }).Count
    }
    try { Write-QLog ("Apps selections discovered in Play handler: {0}" -f $appsSelectedCount) "INFO" } catch { }

    if ($appsSelectedCount -gt 0) {
        $selectedTasks.Add(@{ Name = "Run selected app actions"; ScriptPath = Join-Path $scriptsRoot "Apps\Apps.RunSelected.ps1" }) | Out-Null
    }

    if ($selectedTasks.Count -eq 0) {
        Write-Host "No tasks selected."
        Write-Host "No more tasks to do."
        return
    }

    $isAdmin = Test-IsAdmin
    $successCount = 0
    $skippedCount = 0
    $failedCount = 0

    for ($i = 0; $i -lt $selectedTasks.Count; $i++) {
        $task = $selectedTasks[$i]
        $taskName = $task.Name
        $scriptPath = $task.ScriptPath
        $requiresAdmin = $false
        if ($task.ContainsKey("RequiresAdmin")) {
            $requiresAdmin = [bool]$task.RequiresAdmin
        }
        if ([string]::IsNullOrWhiteSpace($taskName)) { $taskName = "UnknownTask" }

        Write-Host "Now doing task: $taskName"
        if ($requiresAdmin -and -not $isAdmin) {
            Write-Host "WARN: Task requires admin rights. Some changes may be blocked."
        }

        $taskStatus = "FAILED"
        $taskReason = $null
        
        try {
            if ([string]::IsNullOrWhiteSpace($scriptPath)) {
                throw "No script path found for task '$taskName'."

            }
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                throw "Script path does not exist: $scriptPath"
            }

            $result = & {
                $ErrorActionPreference = 'Stop'
                $resultReason = $null
                $resultError = $null
                & $scriptPath -Window $activeWindow
            }
            $resultStatus = $null
            if ($null -ne $result) {
                foreach ($entry in @($result)) {
                    if ($null -eq $entry) { continue }
                    if ($entry.PSObject.Properties.Name -contains "Status") {
                        $resultStatus = [string]$entry.Status
                        if ($entry.PSObject.Properties.Name -contains "Reason") {
                            $resultReason = [string]$entry.Reason
                        }
                        if ($entry.PSObject.Properties.Name -contains "Error") {
                            $resultError = [string]$entry.Error
                        }
                        break
                    }
                }
            }

            if ($resultStatus) {
                switch ($resultStatus.ToLowerInvariant()) {
                    "success" { $taskStatus = "SUCCESS" }
                    "skipped" { $taskStatus = "SKIPPED"; $taskReason = $resultReason }
                    "failed"  { $taskStatus = "FAILED"; $taskReason = $resultReason }
                    default {
                        Write-Host "WARN: Unknown task result status '$resultStatus' for '$taskName'. Treating as FAILED."
                        $taskStatus = "FAILED"
                    }
                }
                if (-not $taskReason -and $resultError) {
                    $taskReason = $resultError
                }
            }
            else {
                $taskStatus = "SUCCESS"
            }
        }
        catch {
            Write-Host "ERROR: Task failed: $taskName | $($_.Exception.Message)"
            $taskStatus = "FAILED"
            $taskReason = $_.Exception.Message
        }
        finally {
            switch ($taskStatus) {
                "SUCCESS" { $successCount++ }
                "SKIPPED" { $skippedCount++ }
                default { $failedCount++ }
            }

            if ($taskStatus -eq "SUCCESS") {
                Write-Host "Completed task: $taskName (SUCCESS)"
            }
            elseif ($taskStatus -eq "SKIPPED") {
                Write-Host "Skipped task: $taskName"
            }
            else {
                if ([string]::IsNullOrWhiteSpace($taskReason)) {
                    $taskReason = "Unknown error"
                }
                Write-Host "Completed task: $taskName (FAILED - $taskReason)"
            }
            if ($ProgressPath -and $ProgressClip) {
                $pct = [math]::Round((($i + 1) / [double]$selectedTasks.Count) * 100, 0)
                Set-QOTPlayProgress -ProgressPath $ProgressPath -ProgressClip $ProgressClip -Percent $pct
            }
        }
    }
    Write-Host "Summary: Success=$successCount Skipped=$skippedCount Failed=$failedCount"
    Write-Host "No more tasks to do."
}

function Find-QOTControlByNameDeep {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Root -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        if ($Root -is [System.Windows.FrameworkElement]) {
            $direct = $Root.FindName($Name)
            if ($direct) { return $direct }
        }
    } catch { }

    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $q = New-Object 'System.Collections.Generic.Queue[System.Object]'
    $q.Enqueue($Root) | Out-Null

    while ($q.Count -gt 0) {
        $cur = $q.Dequeue()
        if (-not $cur) { continue }

        $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
        if (-not $visited.Add($objId)) { continue }

        if ($cur -is [System.Windows.FrameworkElement]) {
            if ($cur.Name -eq $Name) { return $cur }
            try {
                $withinScope = $cur.FindName($Name)
                if ($withinScope) { return $withinScope }
            } catch { }
        } elseif ($cur -is [System.Windows.FrameworkContentElement]) {
            if ($cur.Name -eq $Name) { return $cur }
        }

        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                if ($child) { $q.Enqueue($child) | Out-Null }
            }
        } catch { }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur)
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                }
            } catch { }
        }
    }

    return $null
}

function Show-QOTStartupErrorBanner {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$Message
    )

    $banner = Find-QOTControlByNameDeep -Root $Window -Name "ExecutionMessage"
    if (-not $banner) {
        Write-QOTStartupTrace ("Startup error banner control not found. Message: {0}" -f $Message) 'ERROR'
        return
    }

    $banner.Text = $Message
    $banner.Visibility = [System.Windows.Visibility]::Visible
}

function Get-QOTNamedElementsMap {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root
    )

    $map = @{}

    try {
        $q = New-Object 'System.Collections.Generic.Queue[System.Windows.DependencyObject]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()

            if ($cur -is [System.Windows.FrameworkElement]) {
                $n = $cur.Name
                if (-not [string]::IsNullOrWhiteSpace($n)) {
                    if (-not $map.ContainsKey($n)) {
                        $map[$n] = $cur.GetType().FullName
                    }
                }
            }

            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }

            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    } catch { }

    return $map
}

function Get-QOTNamedElementsSnapshot {
    param(
        [Parameter(Mandatory)][System.Windows.DependencyObject]$Root,
        [int]$MaxCount = 30
    )

    $result = New-Object System.Collections.ArrayList
    $seenNames = New-Object 'System.Collections.Generic.HashSet[string]'
    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $queue = New-Object 'System.Collections.Generic.Queue[System.Object]'
    $queue.Enqueue($Root) | Out-Null

    while ($queue.Count -gt 0 -and $result.Count -lt $MaxCount) {
        $cur = $queue.Dequeue()
        if (-not $cur) { continue }

        $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cur)
        if (-not $visited.Add($objId)) { continue }

        if ($cur -is [System.Windows.FrameworkElement] -or $cur -is [System.Windows.FrameworkContentElement]) {
            $name = $cur.Name
            if (-not [string]::IsNullOrWhiteSpace($name) -and $seenNames.Add($name)) {
                [void]$result.Add([pscustomobject]@{ Name = $name; Type = $cur.GetType().FullName })
            }
        }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) {
                    if ($child) { $queue.Enqueue($child) | Out-Null }
                }
            }
            catch {
                Write-QOTStartupTrace ("Named elements snapshot logical-tree walk skipped for {0}: {1}" -f $cur.GetType().FullName, $_.Exception.Message) 'DEBUG'
            }
        }

        if ($cur -is [System.Windows.DependencyObject]) {
            try {
                $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur)
                for ($i = 0; $i -lt $count; $i++) {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $queue.Enqueue($child) | Out-Null }
                }
            } catch { }
        }
    }

    return @($result)
}

function Write-QOTWindowVisibilityDiagnostics {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [string]$Prefix = "MainWindow"
    )

    $diagnostic = "{0} visibility: IsVisible={1}; Visibility={2}; WindowState={3}; Left={4}; Top={5}; Width={6}; Height={7}; Opacity={8}; ShowInTaskbar={9}" -f `
        $Prefix, $Window.IsVisible, $Window.Visibility, $Window.WindowState, $Window.Left, $Window.Top, $Window.Width, $Window.Height, $Window.Opacity, $Window.ShowInTaskbar
    Write-QOTStartupTrace $diagnostic

    $app = [System.Windows.Application]::Current
    if ($app) {
        $currentMainWindowType = if ($app.MainWindow) { $app.MainWindow.GetType().FullName } else { '<null>' }
        Write-QOTStartupTrace ("Application.Current.MainWindow currently: {0}" -f $currentMainWindowType)
    } else {
        Write-QOTStartupTrace "Application.Current is null while logging visibility diagnostics" 'WARN'
    }
}

function Ensure-QOTWpfApplication {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $existing = [System.Windows.Application]::Current
    if ($existing) {
        Write-QOTStartupTrace ("Using existing WPF Application instance: {0}" -f $existing.GetType().FullName)
        if (-not $existing.MainWindow -or -not [object]::ReferenceEquals($existing.MainWindow, $Window)) {
            $existing.MainWindow = $Window
            Write-QOTStartupTrace ("Application.Current.MainWindow assigned to: {0}" -f $Window.GetType().FullName)
        }

        return [pscustomobject]@{
            Application = $existing
            CreatedHere = $false
        }
    }

    $created = [System.Windows.Application]::new()
    $created.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
    $created.MainWindow = $Window
    Write-QOTStartupTrace ("Created new WPF Application instance: {0}" -f $created.GetType().FullName)
    Write-QOTStartupTrace ("Application.Current.MainWindow assigned to: {0}" -f $Window.GetType().FullName)

    return [pscustomobject]@{
        Application = $created
        CreatedHere = $true
    }
}

function Set-QOTWindowSafetyDefaults {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $Window.WindowState = [System.Windows.WindowState]::Normal
    $Window.Visibility = [System.Windows.Visibility]::Visible
    $Window.ShowInTaskbar = $true
    $Window.Opacity = 1

    $virtualLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
    $virtualTop = [System.Windows.SystemParameters]::VirtualScreenTop
    $virtualWidth = [System.Windows.SystemParameters]::VirtualScreenWidth
    $virtualHeight = [System.Windows.SystemParameters]::VirtualScreenHeight

    $hasInvalidLeft = [double]::IsNaN($Window.Left) -or [double]::IsInfinity($Window.Left)
    $hasInvalidTop = [double]::IsNaN($Window.Top) -or [double]::IsInfinity($Window.Top)
    $hasOffscreenLeft = ($Window.Left -lt $virtualLeft) -or ($Window.Left -gt ($virtualLeft + $virtualWidth))
    $hasOffscreenTop = ($Window.Top -lt $virtualTop) -or ($Window.Top -gt ($virtualTop + $virtualHeight))

    if ($hasInvalidLeft -or $hasInvalidTop -or $hasOffscreenLeft -or $hasOffscreenTop) {
        $width = if ($Window.Width -gt 0) { $Window.Width } else { 1200 }
        $height = if ($Window.Height -gt 0) { $Window.Height } else { 800 }
        $Window.Left = $virtualLeft + (($virtualWidth - $width) / 2)
        $Window.Top = $virtualTop + (($virtualHeight - $height) / 2)
    }
}

function Start-QOTMainWindow {
    param(
        [Parameter(Mandatory)]
        $SplashWindow,

        [switch]$WarmupOnly,
        [switch]$PassThru
    )

    $basePath = Join-Path $PSScriptRoot ".."

    # ------------------------------------------------------------
    # Core modules
    # ------------------------------------------------------------
    Invoke-QOTStartupStep "Core module imports" {
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Config\Config.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Logging\Logging.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Settings.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Tickets.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Actions\ActionRegistry.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Actions\ActionsCatalog.psm1") -Optional
    }

    # ------------------------------------------------------------
    # Apps modules (data + engine)
    # ------------------------------------------------------------
    Invoke-QOTStartupStep "Apps module imports" {
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Apps\InstalledApps.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Apps\InstallCommonApps.psm1")
    }

    # ------------------------------------------------------------
    # UI modules (import if not already loaded)
    # ------------------------------------------------------------
    Invoke-QOTStartupStep "UI module imports" {
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Tickets\Tickets.UI.psm1") -Global
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "UI\HelpWindow.UI.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Core\Settings\Settings.UI.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Apps\Apps.UI.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "TweaksAndCleaning\CleaningAndMain\TweaksAndCleaning.UI.psm1")
        Import-QOTModuleIfNeeded -Path (Join-Path $basePath "Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1")
    }

    if (-not (Get-Command Write-QOTicketsUILog -ErrorAction SilentlyContinue)) {
        function global:Write-QOTicketsUILog {
            param(
                [Parameter(Mandatory = $true)][string]$Message,
                [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
            )

            try {
                if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
                    Write-QLog $Message $Level
                    return
                }
            } catch { }

            try { Write-Host ("[Tickets.UI] " + $Level + ": " + $Message) } catch { }
        }
    }

    # ------------------------------------------------------------
    # Load MainWindow XAML
    # ------------------------------------------------------------
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "MainWindow.xaml not found at $xamlPath"
    }
    Write-QOTStartupTrace "START MainWindow build begin"
    try { Write-QLog ("Loading XAML from: {0}" -f $xamlPath) "DEBUG" } catch { }

    try {
        $xaml   = Get-Content -LiteralPath $xamlPath -Raw
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
        Write-Host "Loaded XAML OK"
        Write-QOTStartupTrace "XAML load OK"
        Write-QOTStartupTrace "InitializeComponent OK"
    }
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("MainWindow XAML load failed from {0}`n{1}" -f $xamlPath, $errorDetail) 'ERROR'
        try { Write-QLog ("MainWindow XAML load failed from {0}`n{1}" -f $xamlPath, $errorDetail) "ERROR" } catch { }
        throw
    }

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    Write-QOTStartupTrace ("MainWindow XAML path: {0}" -f ([System.IO.Path]::GetFullPath($xamlPath)))
    Write-QOTStartupTrace ("MainWindow root type: {0}" -f $window.GetType().FullName)
    try {
        $namedSnapshot = Get-QOTNamedElementsSnapshot -Root $window -MaxCount 30
        if ($namedSnapshot.Count -gt 0) {
            Write-QOTStartupTrace ("First {0} named elements: {1}" -f $namedSnapshot.Count, (($namedSnapshot | ForEach-Object { "{0}<{1}>" -f $_.Name, $_.Type }) -join ', '))
        }
        else {
            Write-QOTStartupTrace "First named elements: none discovered" 'WARN'
        }
    } catch {
        Write-QOTStartupTrace ("Failed to enumerate named elements snapshot: {0}" -f $_.Exception.Message) 'WARN'
    }

    $script:MainWindow = $window
    $applicationState = Ensure-QOTWpfApplication -Window $window
    $app = $applicationState.Application
    $appCreatedHere = [bool]$applicationState.CreatedHere

    if (-not [System.Windows.Application]::Current) {
        Write-QOTStartupTrace "Application.Current is unexpectedly null after Ensure-QOTWpfApplication" 'ERROR'
        throw "WPF Application instance was not available after initialisation."
    }
    $script:SummaryTextBlock = Find-QOTControlByNameDeep -Root $script:MainWindow -Name "SummaryText"

    $window.Add_Loaded({
        Write-QOTStartupTrace "MainWindow.Loaded fired"
    })
    $window.Add_ContentRendered({
        Write-QOTStartupTrace "MainWindow ContentRendered event fired"
    })

    if (Get-Command Clear-QOTActionGroups -ErrorAction SilentlyContinue) {
        Clear-QOTActionGroups
    }
    if (Get-Command Clear-QOTActionDefinitions -ErrorAction SilentlyContinue) {
        Clear-QOTActionDefinitions
    }

    $requiredControls = @(
        "MainTabControl","BtnPlay","AppsGrid","InstallGrid",
        "TicketsGrid","BtnRefreshTickets","BtnNewTicket","BtnDeleteTicket",
        "SettingsHost","HelpHost","TabTickets"
    )
    $controlResolution = Invoke-QOTControlResolution -Root $script:MainWindow -Names $requiredControls
    $resolvedControls = $controlResolution.Resolved
    $missingControls = @($controlResolution.Missing)

    try {
        foreach ($controlName in $requiredControls) {
            if ($resolvedControls.ContainsKey($controlName)) {
                $controlType = $resolvedControls[$controlName].GetType().FullName
                Write-QOTStartupTrace ("Control resolved from MainWindow instance: {0} ({1})" -f $controlName, $controlType) 'DEBUG'
            }
            else {
                Write-QOTStartupTrace ("Control unresolved from MainWindow instance: {0}" -f $controlName) 'WARN'
            }
        }
    } catch { }

    if ($missingControls.Count -eq 0) {
        Write-QOTStartupTrace ("UI controls resolved: OK ({0}/{1})" -f $resolvedControls.Count, $requiredControls.Count)
    } else {
        Write-QOTStartupTrace ("UI controls resolution FAILED ({0}/{1}). Missing: {2}" -f $resolvedControls.Count, $requiredControls.Count, ($missingControls -join ', ')) 'WARN'
    }

    $criticalRequiredControls = @("BtnPlay", "MainTabControl")
    $criticalMissing = @($criticalRequiredControls | Where-Object { -not $resolvedControls.ContainsKey($_) })
    $hasCriticalResolutionFailure = ($criticalMissing.Count -gt 0)
    if ($hasCriticalResolutionFailure) {
        $fatalMessage = "Critical UI controls missing: {0}. Modules (Apps/Tickets/Tweaks) will not be wired." -f ($criticalMissing -join ', ')
        Write-QOTStartupTrace $fatalMessage 'ERROR'
        try { Write-QLog $fatalMessage 'ERROR' } catch { }
        Show-QOTStartupErrorBanner -Window $window -Message $fatalMessage
    }

    $extraControlResolution = Invoke-QOTControlResolution -Root $script:MainWindow -Names @("TabApps","BtnPlayProgressPath","BtnPlayProgressClip","ExecutionMessage","BtnSettings","BtnHelp","TabHelp","TabSettings")
    foreach ($kv in $extraControlResolution.Resolved.GetEnumerator()) {
        if (-not $resolvedControls.ContainsKey($kv.Key)) {
            $resolvedControls[$kv.Key] = $kv.Value
        }
    }

    $tabs    = $resolvedControls["MainTabControl"]
    $tabApps = $resolvedControls["TabApps"]

    # ------------------------------------------------------------
    # Initialise Apps UI
    # ------------------------------------------------------------
    if (-not $hasCriticalResolutionFailure) {
        try {
            if (-not (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTAppsUI not found. Apps\Apps.UI.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise Apps UI" { $script:AppsUIInitialised = [bool](Initialize-QOTAppsUI -Window $window) }
            Write-QOTStartupTrace "Initialise Apps UI OK"
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Apps UI failed to load; continuing startup.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Apps UI failed to load; continuing startup.`n{0}" -f $errorDetail) "ERROR" } catch { }
        }

    # ------------------------------------------------------------
    # Initialise Tickets UI
    # ------------------------------------------------------------
        try {
        if (-not (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTicketsUI not found. Tickets\Tickets.UI.psm1 did not load or export correctly."
        }
        if (-not (Get-Command Invoke-QOTicketsFilterSafely -ErrorAction SilentlyContinue)) {
            throw "Invoke-QOTicketsFilterSafely not found after Tickets UI module import."
        }
        Invoke-QOTStartupStep "Initialise Tickets UI" { $script:TicketsUIInitialised = [bool](Initialize-QOTicketsUI -Window $window) }
        }
        catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("Tickets UI failed to load; startup halted.`n{0}" -f $errorDetail) 'ERROR'
        try { Write-QLog ("Tickets UI failed to load; startup halted.`n{0}" -f $errorDetail) "ERROR" } catch { }
        throw
        }

    # ------------------------------------------------------------
    # Initialise Tweaks & Cleaning UI
    # ------------------------------------------------------------
        try {
            if (-not (Get-Command Initialize-QOTActionCatalog -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTActionCatalog not found. Core\\Actions\\ActionsCatalog.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise action catalog" { Initialize-QOTActionCatalog }
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Action catalog failed to initialise; startup halted.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Action catalog failed to initialise; startup halted.`n{0}" -f $errorDetail) "ERROR" } catch { }
            throw
        }

    # ------------------------------------------------------------
    # Initialise Advanced Tweaks UI
    # ------------------------------------------------------------
        try {
            if (-not (Get-Command Initialize-QOTTweaksAndCleaningUI -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTTweaksAndCleaningUI not found. TweaksAndCleaning.UI.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise Tweaks UI" { Initialize-QOTTweaksAndCleaningUI -Window $window }
            Write-QOTStartupTrace "Initialise Tweaks UI OK"
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Tweaks/Cleaning UI failed to load; startup halted.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Tweaks/Cleaning UI failed to load; startup halted.`n{0}" -f $errorDetail) "ERROR" } catch { }
            throw
        }

    # ------------------------------------------------------------
    # Register action catalog (central ActionId mappings)
    # ------------------------------------------------------------
        try {
            if (-not (Get-Command Initialize-QOTAdvancedTweaksUI -ErrorAction SilentlyContinue)) {
                throw "Initialize-QOTAdvancedTweaksUI not found. AdvancedTweaks.UI.psm1 did not load or export correctly."
            }

            Invoke-QOTStartupStep "Initialise Advanced UI" { Initialize-QOTAdvancedTweaksUI -Window $window }
            Write-QOTStartupTrace "Initialise Advanced UI OK"
        }
        catch {
            $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
            Write-QOTStartupTrace ("Advanced UI failed to load; continuing startup.`n{0}" -f $errorDetail) 'ERROR'
            try { Write-QLog ("Advanced UI failed to load; continuing startup.`n{0}" -f $errorDetail) "ERROR" } catch { }
        }



    # ------------------------------------------------------------
   # Wire Play button (global action registry)
    # ------------------------------------------------------------
        $btnPlay = $resolvedControls["BtnPlay"]
        $playProgressPath = $resolvedControls["BtnPlayProgressPath"]
        $playProgressClip = $resolvedControls["BtnPlayProgressClip"]
        $executionMessage = $resolvedControls["ExecutionMessage"]

    if ($btnPlay) {
        $null = Set-QOTUIEnabledState -Control $btnPlay -IsEnabled $true
        $null = Set-QOTHitTestVisibility -Control $btnPlay -IsHitTestVisible $true
        Set-QOTPlayProgress -ProgressPath $playProgressPath -ProgressClip $playProgressClip -Percent 0

        $btnPlay.Add_Click({
            Write-Host "User clicked Play button"
            try {
                if ($script:IsPlayRunning) { return }

                $activeWindow = $script:MainWindow
                if (-not $activeWindow) {
                    $activeWindow = [System.Windows.Window]::GetWindow($this)
                }
                if (-not $activeWindow) {
                    throw "Main window reference is not available for Play button execution."
                }
                
                if ($executionMessage) {
                    $executionMessage.Visibility = [System.Windows.Visibility]::Collapsed
                    $executionMessage.Text = ""
                }

                $script:IsPlayRunning = $true
                Set-QOTPlayProgress -ProgressPath $playProgressPath -ProgressClip $playProgressClip -Percent 0



                Run-QOTSelectedTasks -Window $activeWindow -ProgressPath $playProgressPath -ProgressClip $playProgressClip

                Invoke-QOTPlayCompletionSound
            }
            catch {
                Write-Host "Play button handler failed: $($_.Exception.Message)"
            }
            finally {
                Set-QOTPlayProgress -ProgressPath $playProgressPath -ProgressClip $playProgressClip -Percent 0
                $script:IsPlayRunning = $false
                $null = Set-QOTUIEnabledState -Control $btnPlay -IsEnabled $true
                $null = Set-QOTHitTestVisibility -Control $btnPlay -IsHitTestVisible $true
            }
        })
    }


    # ------------------------------------------------------------
    # Initialise Settings UI (hosted in SettingsHost)
    # ------------------------------------------------------------
        $settingsHost = $resolvedControls["SettingsHost"]
        if (-not $settingsHost) {
            throw "SettingsHost not found. Check MainWindow.xaml contains: <ContentControl x:Name='SettingsHost' />"
        }

    try {
        $cmd = Get-Command New-QOTSettingsView -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "New-QOTSettingsView not found. Check Core\Settings\Settings.UI.psm1 exports it."
        }

        $settingsView = $null
        Invoke-QOTStartupStep "Build settings view" { $settingsView = New-QOTSettingsView -Window $window }
        if (-not $settingsView) { throw "Settings view returned null" }

        $settingsHost.Content = $settingsView
    }
    catch {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Settings failed to load.`r`n$($_.Exception.Message)"
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        $tb.Margin = "10"
        $settingsHost.Content = $tb
    }
    # ------------------------------------------------------------
    # Initialise Help UI (hosted in HelpHost)
    # ------------------------------------------------------------
        $helpHost = $resolvedControls["HelpHost"]
        if (-not $helpHost) {
            throw "HelpHost not found. Check MainWindow.xaml contains: <ContentControl x:Name='HelpHost' />"
        }

    try {
        $cmd = Get-Command New-QOTHelpView -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "New-QOTHelpView not found. Check UI\HelpWindow.UI.psm1 exports it."
        }

        $helpView = $null
        Invoke-QOTStartupStep "Build help view" { $helpView = New-QOTHelpView }
        if (-not $helpView) { throw "Help view returned null" }

        $helpHost.Content = $helpView
    }
    catch {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Help failed to load.`r`n$($_.Exception.Message)"
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        $tb.Margin = "10"
        $helpHost.Content = $tb
    }


    # ------------------------------------------------------------
    # Gear icon switches to Settings tab (tab is hidden)
    # ------------------------------------------------------------
        $btnSettings = $resolvedControls["BtnSettings"]
        $btnHelp     = $resolvedControls["BtnHelp"]
        $tabHelp     = $resolvedControls["TabHelp"]
        $tabSettings = $resolvedControls["TabSettings"]
        
        if ($btnSettings -and $tabs -and $tabSettings) {
            $btnSettings.Add_Click({
                $tabs.SelectedItem = $tabSettings
            })
        }

        if ($btnHelp -and $tabs -and $tabHelp) {
            $btnHelp.Add_Click({
                $tabs.SelectedItem = $tabHelp
            })
        }
    }
    else {
        Write-QOTStartupTrace "Critical UI controls are missing; feature module wiring skipped." 'WARN'
    }
    
    # ------------------------------------------------------------
    # System summary refresh
    # ------------------------------------------------------------
    if ($script:SummaryTextBlock) {
        Invoke-QOTStartupStep "Initial system summary" { Set-QOTSummary -Text (Get-QOTSystemSummaryText) }
        $script:SummaryTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:SummaryTimer.Interval = [TimeSpan]::FromSeconds(5)
        $script:SummaryTimer.Add_Tick({
            Set-QOTSummary -Text (Get-QOTSystemSummaryText)
        })
        $script:SummaryTimer.Start()
    }

    # ------------------------------------------------------------
    # Close splash + show main window
    # ------------------------------------------------------------
    if ($WarmupOnly) {
        if ($PassThru) { return $window }
        return
    }
    try {
        try { if ($SplashWindow) { $SplashWindow.Close() } } catch { }
        Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow pre-show"

        Write-QOTStartupTrace "Calling MainWindow.Show()"
        $window.Show()
        $window.Activate() | Out-Null
        Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow post-show"
        
        if ($appCreatedHere) {
            Set-QOTWindowSafetyDefaults -Window $window
            if (-not $window.IsVisible -or $window.Visibility -ne [System.Windows.Visibility]::Visible) {
                Write-QOTStartupTrace "MainWindow not visible after Show; re-showing with safety defaults" 'WARN'
                $window.Show()
                $window.Activate() | Out-Null
                Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow post-safety-show"
            }
        }
        else {

            if (-not $window.IsVisible -or $window.Visibility -ne [System.Windows.Visibility]::Visible) {
                Write-QOTStartupTrace "MainWindow not visible after Show; applying safety defaults" 'WARN'
                Set-QOTWindowSafetyDefaults -Window $window
                $window.Show()
                $window.Activate() | Out-Null
                Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow post-safety-show"
            }

            if (-not $window.ShowInTaskbar -or $window.Opacity -lt 1) {
                Write-QOTStartupTrace "MainWindow taskbar/opacity defaults were not normal; enforcing safety defaults" 'WARN'
                Set-QOTWindowSafetyDefaults -Window $window
                Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow post-taskbar-opacity-fix"
            }
        }
        if (-not $app) {
            throw "WPF Application instance is null before Run()."
        }
        if (-not $window) {
            throw "MainWindow instance is null before Run()."
        }

        $currentApartmentState = [System.Threading.Thread]::CurrentThread.GetApartmentState()
        Write-QOTStartupTrace ("CurrentThread.ApartmentState before Run: {0}" -f $currentApartmentState)

        $app.MainWindow = $window
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
        Write-QOTStartupTrace ("Application ShutdownMode set to: {0}" -f $app.ShutdownMode)

        $window.Add_Loaded({ Write-QOTStartupTrace "MainWindow lifecycle event fired: Loaded" })
        $window.Add_ContentRendered({ Write-QOTStartupTrace "MainWindow lifecycle event fired: ContentRendered" })
        $window.Add_Closing({
            param($sender, $eventArgs)
            Write-QOTStartupTrace ("MainWindow lifecycle event fired: Closing (Cancel={0})" -f $eventArgs.Cancel)
        })
        $window.Add_Closed({ Write-QOTStartupTrace "MainWindow lifecycle event fired: Closed" })

        Write-QOTStartupTrace "Forcing MainWindow.Show() + Activate() immediately before Run"
        $window.Show()
        $window.Activate() | Out-Null
        Write-QOTWindowVisibilityDiagnostics -Window $window -Prefix "MainWindow pre-run forced-show"

        Write-QOTStartupTrace "Entering app.Run(mainWindow)"
        try {
            $app.Run($window) | Out-Null
            Write-QOTStartupTrace "app.Run(mainWindow) exited normally"
        }
        catch {
            $runExceptionText = if ($_.Exception) { $_.Exception.ToString() } else { $_.ToString() }
            Write-QOTStartupTrace ("app.Run(mainWindow) threw an exception.`n{0}" -f $runExceptionText) 'ERROR'
            try { Write-QLog ("app.Run(mainWindow) threw an exception.`n{0}" -f $runExceptionText) "ERROR" } catch { }
            throw
        }
    }
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("MainWindow show failed.`n{0}" -f $errorDetail) 'ERROR'
        try { Write-QLog ("MainWindow show failed.`n{0}" -f $errorDetail) "ERROR" } catch { }
        throw
    }

    if ($PassThru) { return $window }
}

Export-ModuleMember -Function Start-QOTMainWindow, Set-QOTSummary, Resolve-QOTControlSet
