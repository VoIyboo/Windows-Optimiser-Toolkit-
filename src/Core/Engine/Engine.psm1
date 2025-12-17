# Engine.psm1
# Coordinates major operations by calling the feature modules

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Config\Config.psm1"   -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue

# Import feature modules (best effort)
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\CleaningAndMain\Cleaning.psm1"         -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force -ErrorAction SilentlyContinue

# Apps
Import-Module "$PSScriptRoot\..\..\Apps\InstalledApps.psm1"     -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\..\Apps\InstallCommonApps.psm1" -Force -ErrorAction SilentlyContinue

# Advanced
Import-Module "$PSScriptRoot\..\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1"   -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\..\Advanced\NetworkAndServices\NetworkAndServices.psm1" -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# Small helpers used by the UI
# ------------------------------------------------------------
function Set-QOTStatus {
    param([string]$Text)

    try { Write-QLog "STATUS: $Text" } catch { }

    if (Get-Command Set-QOTSummary -ErrorAction SilentlyContinue) {
        Set-QOTSummary -Text $Text
    }
}

function Set-QOTProgress {
    param([int]$Percent)

    try { Write-QLog "Progress: $Percent%" } catch { }
}

# ------------------------------------------------------------
# Run button logic
# ------------------------------------------------------------
function Invoke-QOTRun {
    try { Write-QLog "Starting full run" } catch { }
    Set-QOTStatus "Running..."
    Set-QOTProgress 0

    try {
        if (Get-Command Start-QOTCleaning -ErrorAction SilentlyContinue) {
            Start-QOTCleaning
        }
        Set-QOTProgress 33

        if (Get-Command Start-QOTTweaks -ErrorAction SilentlyContinue) {
            Start-QOTTweaks
        }
        Set-QOTProgress 66

        try { Write-QLog "Run completed" } catch { }
        Set-QOTProgress 100
        Set-QOTStatus "Completed"
    }
    catch {
        try { Write-QLog "Error during run: $($_.Exception.Message)" "ERROR" } catch { }
        Set-QOTStatus "Error occurred"
    }
}

# ------------------------------------------------------------
# Advanced Run
# ------------------------------------------------------------
function Invoke-QOTAdvancedRun {
    try { Write-QLog "Starting Advanced run" } catch { }
    Set-QOTStatus "Running Advanced Tasks..."

    try {
        if (Get-Command Start-QOTAdvancedCleaning -ErrorAction SilentlyContinue) {
            Start-QOTAdvancedCleaning
        }
        if (Get-Command Start-QOTNetworkFix -ErrorAction SilentlyContinue) {
            Start-QOTNetworkFix
        }

        try { Write-QLog "Advanced run completed" } catch { }
        Set-QOTStatus "Advanced Completed"
    }
    catch {
        try { Write-QLog "Error in advanced run: $($_.Exception.Message)" "ERROR" } catch { }
        Set-QOTStatus "Advanced Error"
    }
}

# ------------------------------------------------------------
# Start-QOTMain: entry point for main UI
# ------------------------------------------------------------
function New-QOTSplashWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Loading..."
        Height="220" Width="520"
        WindowStartupLocation="CenterScreen"
        Background="#0F172A"
        WindowStyle="None"
        AllowsTransparency="True"
        Topmost="True"
        ShowInTaskbar="False">
    <Border Background="#020617" BorderBrush="#374151" BorderThickness="1" CornerRadius="12" Padding="18">
        <StackPanel>
            <TextBlock Text="Quinn Optimiser Toolkit" Foreground="White" FontSize="20" FontWeight="SemiBold"/>
            <TextBlock Text="Loading components..." Foreground="#9CA3AF" Margin="0,6,0,18"/>
            <ProgressBar Height="10" IsIndeterminate="True" Background="#1E293B" Foreground="#2563EB"/>
        </StackPanel>
    </Border>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

function Invoke-QOTStartupWarmup {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    # Put your "slow stuff" here.
    # Keep it safe: no UI touching inside this function.
    try { Write-QLog "Startup warmup: begin" } catch { }

    # Example warmups (adjust to taste):
    try {
        if (Get-Command Test-QOTWingetAvailable -ErrorAction SilentlyContinue) {
            $null = Test-QOTWingetAvailable
        }
    } catch { }

    try {
        if (Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue) {
            $null = Get-QOTCommonAppsCatalogue
        }
    } catch { }

    try { Write-QLog "Startup warmup: end" } catch { }
}

function Start-QOTMain {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    try { Write-QLog "Start-QOTMain called. Root = $RootPath" } catch { }

    # Safety net: load UI module if it is not already loaded
    if (-not (Get-Command Start-QOTMainWindow -ErrorAction SilentlyContinue)) {

        $uiModule = Join-Path $PSScriptRoot "..\..\UI\MainWindow.UI.psm1"
        $uiModule = [System.IO.Path]::GetFullPath($uiModule)

        if (-not (Test-Path -LiteralPath $uiModule)) {
            throw "UI module file missing: $uiModule"
        }

        Import-Module $uiModule -Force -ErrorAction Stop
    }

    if (-not (Get-Command Start-QOTMainWindow -ErrorAction SilentlyContinue)) {
        throw "UI module not loaded: Start-QOTMainWindow not found"
    }

    # Show splash first
    $splash = $null
    try {
        $splash = New-QOTSplashWindow
        $null = $splash.Show()
        $splash.Activate()
    } catch {
        # If splash fails, do not block startup
        try { Write-QLog "Splash failed: $($_.Exception.Message)" "WARN" } catch { }
    }

    # Run warmup on a background thread so the splash stays responsive
    $task = [System.Threading.Tasks.Task]::Run([Action]{
        Invoke-QOTStartupWarmup -RootPath $RootPath
    })

    # Keep UI responsive while we wait
    while (-not $task.IsCompleted) {
        try {
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
                [Action]{ },
                [System.Windows.Threading.DispatcherPriority]::Background
            )
        } catch { }
        Start-Sleep -Milliseconds 50
    }

    # Close splash, then show main window
    try { if ($splash) { $splash.Close() } } catch { }

    Start-QOTMainWindow
}

Export-ModuleMember -Function `
    Start-QOTMain, `
    Invoke-QOTRun, `
    Invoke-QOTAdvancedRun, `
    Set-QOTStatus, `
    Set-QOTProgress
