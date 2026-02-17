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

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$ts] [STARTUP] $Message"

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $line $Level
        }
    } catch { }

    try { Write-Host $line } catch { }
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

    try { Write-QLog ("Loading XAML from: {0}" -f $xamlPath) "DEBUG" } catch { }

    Write-QOTStartupTrace "MainWindow InitializeComponent start"
    try {
        $xaml   = Get-Content -LiteralPath $xamlPath -Raw
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
        Write-Host "Loaded XAML OK"
        Write-QOTStartupTrace "Loaded XAML OK"
    }
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("MainWindow XAML load failed from {0}`n{1}" -f $xamlPath, $errorDetail) 'ERROR'
        try { Write-QLog ("MainWindow XAML load failed from {0}`n{1}" -f $xamlPath, $errorDetail) "ERROR" } catch { }
        throw
    }
    Write-QOTStartupTrace "MainWindow InitializeComponent end"

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    $script:MainWindow = $window
    $script:SummaryTextBlock = $window.FindName("SummaryText")

    $window.Add_Loaded({
        Write-QOTStartupTrace "MainWindow Loaded event fired"
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

    # ------------------------------------------------------------
    # Optional: log key names present in LOADED XAML
    # ------------------------------------------------------------
    try {
        $map = Get-QOTNamedElementsMap -Root $window
        $wanted = @(
            "AppsGrid","InstallGrid","BtnScanApps","BtnUninstallSelected","BtnPlay",
            "SettingsHost","HelpHost","BtnSettings","BtnHelp","MainTabControl","TabSettings","TabHelp",
            "TabTickets","TicketsGrid","BtnRefreshTickets","BtnNewTicket","BtnDeleteTicket"
        )

        foreach ($k in $wanted) {
            if ($map.ContainsKey($k)) {
                Write-QLog ("Found control: {0} ({1})" -f $k, $map[$k]) "DEBUG"
            } else {
                Write-QLog ("Missing control in loaded XAML: {0}" -f $k) "DEBUG"
            }
        }
    } catch { }

    $tabs    = $window.FindName("MainTabControl")
    $tabApps = $window.FindName("TabApps")

    # ------------------------------------------------------------
    # Initialise Apps UI
    # ------------------------------------------------------------
    try {
        if (-not (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTAppsUI not found. Apps\Apps.UI.psm1 did not load or export correctly."
        }

        Invoke-QOTStartupStep "Initialise Apps UI" { $script:AppsUIInitialised = [bool](Initialize-QOTAppsUI -Window $window) }
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

        Invoke-QOTStartupStep "Initialise Tickets UI" { $script:TicketsUIInitialised = [bool](Initialize-QOTicketsUI -Window $window) }
    }
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("Tickets UI failed to load; continuing startup.`n{0}" -f $errorDetail) 'ERROR'
        try { Write-QLog ("Tickets UI failed to load; continuing startup.`n{0}" -f $errorDetail) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Initialise Tweaks & Cleaning UI
    # ------------------------------------------------------------
    try {
        if (-not (Get-Command Initialize-QOTTweaksAndCleaningUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTTweaksAndCleaningUI not found. TweaksAndCleaning.UI.psm1 did not load or export correctly."
        }

        Invoke-QOTStartupStep "Initialise Tweaks and Cleaning UI" { Initialize-QOTTweaksAndCleaningUI -Window $window }
    }
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("Tweaks/Cleaning UI failed to load; continuing startup.`n{0}" -f $errorDetail) 'ERROR'
        try { Write-QLog ("Tweaks/Cleaning UI failed to load; continuing startup.`n{0}" -f $errorDetail) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Initialise Advanced Tweaks UI
    # ------------------------------------------------------------
    try {
        if (-not (Get-Command Initialize-QOTAdvancedTweaksUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTAdvancedTweaksUI not found. AdvancedTweaks.UI.psm1 did not load or export correctly."
        }

        Invoke-QOTStartupStep "Initialise Advanced Tweaks UI" { Initialize-QOTAdvancedTweaksUI -Window $window }
    }
    catch {
        $errorDetail = Get-QOTExceptionReport -Exception $_.Exception
        Write-QOTStartupTrace ("Advanced UI failed to load; continuing startup.`n{0}" -f $errorDetail) 'ERROR'
        try { Write-QLog ("Advanced UI failed to load; continuing startup.`n{0}" -f $errorDetail) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Register action catalog (central ActionId mappings)
    # ------------------------------------------------------------
    try {
        if (Get-Command Initialize-QOTActionCatalog -ErrorAction SilentlyContinue) {
            Invoke-QOTStartupStep "Initialise action catalog" { Initialize-QOTActionCatalog }
        }
    }
    catch {
        try { Write-QLog ("Action catalog failed to initialise: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }



    # ------------------------------------------------------------
   # Wire Play button (global action registry)
    # ------------------------------------------------------------
    $btnPlay = $window.FindName("BtnPlay")
    $playProgressPath = $window.FindName("BtnPlayProgressPath")
    $playProgressClip = $window.FindName("BtnPlayProgressClip")
    $executionMessage = $window.FindName("ExecutionMessage")

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
    $settingsHost = $window.FindName("SettingsHost")
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
    $helpHost = $window.FindName("HelpHost")
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
    $btnSettings = $window.FindName("BtnSettings")
    $btnHelp     = $window.FindName("BtnHelp")
    $tabHelp     = $window.FindName("TabHelp")
    $tabSettings = $window.FindName("TabSettings")
    $tabTickets  = $window.FindName("TabTickets")

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
    try { if ($SplashWindow) { $SplashWindow.Close() } } catch { }
    $window.ShowDialog() | Out-Null

    if ($PassThru) { return $window }
}

Export-ModuleMember -Function Start-QOTMainWindow, Set-QOTSummary
