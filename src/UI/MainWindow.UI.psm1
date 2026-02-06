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
        [Parameter(Mandatory)]$Window,
        [System.Windows.Shapes.Path]$ProgressPath,
        [System.Windows.Media.RectangleGeometry]$ProgressClip
    )

    # Example task mapping pattern (checkbox/action/script) for fast fallback.
    $taskScriptMap = @{
        "Invoke-QCleanTemp" = "Cleanup\\Invoke-QCleanTemp.ps1"
        "Invoke-QCleanRecycleBin" = "Cleanup\\Invoke-QCleanRecycleBin.ps1"
        "Invoke-QTweakWidgets" = "Tweaks\\Invoke-QTweakWidgets.ps1"
    }

    $selectedTasks = @()
    if (Get-Command Get-QOTSelectedActionsInExecutionOrder -ErrorAction SilentlyContinue) {
        $selectedTasks = @(Get-QOTSelectedActionsInExecutionOrder -Window $Window)
    }

    if ($selectedTasks.Count -eq 0) {
        Write-Host "No tasks selected."
        Write-Host "No more tasks to do."
        return
    }

    for ($i = 0; $i -lt $selectedTasks.Count; $i++) {
        $entry = $selectedTasks[$i]
        $item = $entry.Item
        $actionId = $null
        $taskName = $null

        try { $actionId = $item.ActionId } catch { $actionId = $null }
        try { $taskName = $item.Label } catch { $taskName = $null }
        if ([string]::IsNullOrWhiteSpace($taskName)) { $taskName = $actionId }
        if ([string]::IsNullOrWhiteSpace($taskName)) { $taskName = "UnknownTask" }

        Write-Host "Now doing task: $taskName"

        try {
            $scriptPath = $null
            if (-not [string]::IsNullOrWhiteSpace($actionId) -and (Get-Command Get-QOTActionDefinition -ErrorAction SilentlyContinue)) {
                $definition = Get-QOTActionDefinition -ActionId $actionId
                if ($definition -and -not [string]::IsNullOrWhiteSpace($definition.ScriptPath)) {
                    $scriptPath = $definition.ScriptPath
                }
            }

            if (-not $scriptPath -and -not [string]::IsNullOrWhiteSpace($actionId) -and $taskScriptMap.ContainsKey($actionId)) {
                $scriptPath = Join-Path (Join-Path $PSScriptRoot "..\\Scripts") $taskScriptMap[$actionId]
            }

            if ([string]::IsNullOrWhiteSpace($scriptPath)) {
                throw "No script path found for action '$actionId'."
            }
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                throw "Script path does not exist: $scriptPath"
            }

            & $scriptPath -Window $Window -ErrorAction Stop
            Write-Host "Completed task: $taskName"
        }
        catch {
            Write-Host "Task failed: $taskName - $($_.Exception.Message)"
        }
        finally {
            if ($ProgressPath -and $ProgressClip) {
                $pct = [math]::Round((($i + 1) / [double]$selectedTasks.Count) * 100, 0)
                Set-QOTPlayProgress -ProgressPath $ProgressPath -ProgressClip $ProgressClip -Percent $pct
            }
        }
    }

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
        $SplashWindow
    )

    $basePath = Join-Path $PSScriptRoot ".."

    # ------------------------------------------------------------
    # Core modules
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Core\Config\Config.psm1")    -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Logging\Logging.psm1")  -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Settings.psm1")         -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Tickets.psm1")          -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Actions\ActionRegistry.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Actions\ActionsCatalog.psm1") -Force -ErrorAction SilentlyContinue

    # ------------------------------------------------------------
    # Apps modules (data + engine)
    # ------------------------------------------------------------
    Import-Module (Join-Path $basePath "Apps\InstalledApps.psm1")      -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Apps\InstallCommonApps.psm1")  -Force -ErrorAction Stop

    # ------------------------------------------------------------
    # UI modules (hard reload to avoid ghost handlers)
    # ------------------------------------------------------------
    Remove-Item Function:\Initialize-QOTicketsUI -ErrorAction SilentlyContinue
    Remove-Item Function:\New-QOTSettingsView   -ErrorAction SilentlyContinue
    Remove-Item Function:\New-QOTHelpView       -ErrorAction SilentlyContinue
    Remove-Item Function:\Initialize-QOTAppsUI  -ErrorAction SilentlyContinue
    Remove-Item Function:\Initialize-QOTTweaksAndCleaningUI -ErrorAction SilentlyContinue
    Remove-Item Function:\Initialize-QOTAdvancedTweaksUI -ErrorAction SilentlyContinue

    Get-Module -Name "Tickets.UI"   -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name "HelpWindow.UI" -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name "Settings.UI"  -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name "Apps.UI"      -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name "TweaksAndCleaning.UI" -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name "AdvancedTweaks.UI" -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue

    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Tickets\Tickets.UI.psm1" }            | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\UI\HelpWindow.UI.psm1" }              | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Core\Settings\Settings.UI.psm1" }     | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Apps\Apps.UI.psm1" }                  | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\TweaksAndCleaning\CleaningAndMain\TweaksAndCleaning.UI.psm1" } | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module | Where-Object { $_.Path -and $_.Path -like "*\Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1" } | Remove-Module -Force -ErrorAction SilentlyContinue

    Import-Module (Join-Path $basePath "Tickets\Tickets.UI.psm1")         -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $basePath "UI\HelpWindow.UI.psm1")           -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Core\Settings\Settings.UI.psm1")  -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Apps\Apps.UI.psm1")               -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "TweaksAndCleaning\CleaningAndMain\TweaksAndCleaning.UI.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $basePath "Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1") -Force -ErrorAction Stop

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

    $xaml   = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Failed to load MainWindow from XAML"
    }

    $script:MainWindow = $window
    $script:SummaryTextBlock = $window.FindName("SummaryText")

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

        $script:AppsUIInitialised = [bool](Initialize-QOTAppsUI -Window $window)
    }
    catch {
        try { Write-QLog ("Apps UI failed to load: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Initialise Tickets UI
    # ------------------------------------------------------------
    try {
        if (-not (Get-Command Initialize-QOTicketsUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTicketsUI not found. Tickets\Tickets.UI.psm1 did not load or export correctly."
        }

        $script:TicketsUIInitialised = [bool](Initialize-QOTicketsUI -Window $window)
    }
    catch {
        try { Write-QLog ("Tickets UI failed to load: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Initialise Tweaks & Cleaning UI
    # ------------------------------------------------------------
    try {
        if (-not (Get-Command Initialize-QOTTweaksAndCleaningUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTTweaksAndCleaningUI not found. TweaksAndCleaning.UI.psm1 did not load or export correctly."
        }

        Initialize-QOTTweaksAndCleaningUI -Window $window
    }
    catch {
        try { Write-QLog ("Tweaks/Cleaning UI failed to load: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Initialise Advanced Tweaks UI
    # ------------------------------------------------------------
    try {
        if (-not (Get-Command Initialize-QOTAdvancedTweaksUI -ErrorAction SilentlyContinue)) {
            throw "Initialize-QOTAdvancedTweaksUI not found. AdvancedTweaks.UI.psm1 did not load or export correctly."
        }

        Initialize-QOTAdvancedTweaksUI -Window $window
    }
    catch {
        try { Write-QLog ("Advanced UI failed to load: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }

    # ------------------------------------------------------------
    # Register action catalog (central ActionId mappings)
    # ------------------------------------------------------------
    try {
        if (Get-Command Initialize-QOTActionCatalog -ErrorAction SilentlyContinue) {
            Initialize-QOTActionCatalog
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
        $btnPlay.IsEnabled = $true
        $btnPlay.IsHitTestVisible = $true
        Set-QOTPlayProgress -ProgressPath $playProgressPath -ProgressClip $playProgressClip -Percent 0

        $btnPlay.Add_Click({
            Write-Host "User clicked Play button"
            try {
                if ($script:IsPlayRunning) { return }
                
                if ($executionMessage) {
                    $executionMessage.Visibility = [System.Windows.Visibility]::Collapsed
                    $executionMessage.Text = ""
                }

                $script:IsPlayRunning = $true
                Set-QOTPlayProgress -ProgressPath $playProgressPath -ProgressClip $playProgressClip -Percent 0



                Run-QOTSelectedTasks -Window $window -ProgressPath $playProgressPath -ProgressClip $playProgressClip

                Invoke-QOTPlayCompletionSound
            }
            catch {
                Write-Host "Play button handler failed: $($_.Exception.Message)"
            }
            finally {
                Set-QOTPlayProgress -ProgressPath $playProgressPath -ProgressClip $playProgressClip -Percent 0
                $script:IsPlayRunning = $false
                $btnPlay.IsEnabled = $true
                $btnPlay.IsHitTestVisible = $true
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

        $settingsView = New-QOTSettingsView -Window $window
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

        $helpView = New-QOTHelpView
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
    # Initialise Apps UI after window render, forcing Apps tab to build (tab content is lazy-loaded)
    # ------------------------------------------------------------
    if (-not $script:AppsUIInitialised -and $tabs -and $tabApps -and (Get-Command Initialize-QOTAppsUI -ErrorAction SilentlyContinue)) {
        $window.Add_ContentRendered({
            try {
                if ($script:AppsUIInitialised) { return }

                $prev = $tabs.SelectedItem
                $tabs.SelectedItem = $tabApps

                $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

                if (Initialize-QOTAppsUI -Window $window) {
                    $script:AppsUIInitialised = $true
                }

                if ($prev) { $tabs.SelectedItem = $prev }

                try { Write-QLog "Apps UI initialised after ContentRendered" "DEBUG" } catch { }
            }
            catch {
                try { Write-QLog ("Apps UI failed to load after ContentRendered: {0}" -f $_.Exception.ToString()) "ERROR" } catch { }
            }
        })
    }

    # ------------------------------------------------------------
    # System summary refresh
    # ------------------------------------------------------------
    if ($script:SummaryTextBlock) {
        Set-QOTSummary -Text (Get-QOTSystemSummaryText)
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
    try { if ($SplashWindow) { $SplashWindow.Close() } } catch { }
    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Start-QOTMainWindow, Set-QOTSummary
