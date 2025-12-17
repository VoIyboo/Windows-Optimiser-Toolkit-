# Engine.psm1
# Coordinates major operations by calling the feature modules
# Splash is NOT handled here. Intro.ps1 owns the splash.

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Config\Config.psm1"   -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue

# Import feature modules (best effort)
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\CleaningAndMain\Cleaning.psm1"           -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force -ErrorAction SilentlyContinue

# Apps
Import-Module "$PSScriptRoot\..\..\Apps\InstalledApps.psm1"     -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\..\Apps\InstallCommonApps.psm1" -Force -ErrorAction SilentlyContinue

# Advanced
Import-Module "$PSScriptRoot\..\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1"     -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\..\Advanced\NetworkAndServices\NetworkAndServices.psm1" -Force -ErrorAction SilentlyContinue

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

function Invoke-QOTRun {
    try { Write-QLog "Starting full run" } catch { }
    Set-QOTStatus "Running..."
    Set-QOTProgress 0

    try {
        if (Get-Command Start-QOTCleaning -ErrorAction SilentlyContinue) { Start-QOTCleaning }
        Set-QOTProgress 33

        if (Get-Command Start-QOTTweaks -ErrorAction SilentlyContinue) { Start-QOTTweaks }
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

function Invoke-QOTAdvancedRun {
    try { Write-QLog "Starting Advanced run" } catch { }
    Set-QOTStatus "Running Advanced Tasks..."

    try {
        if (Get-Command Start-QOTAdvancedCleaning -ErrorAction SilentlyContinue) { Start-QOTAdvancedCleaning }
        if (Get-Command Start-QOTNetworkFix -ErrorAction SilentlyContinue) { Start-QOTNetworkFix }

        try { Write-QLog "Advanced run completed" } catch { }
        Set-QOTStatus "Advanced Completed"
    }
    catch {
        try { Write-QLog "Error in advanced run: $($_.Exception.Message)" "ERROR" } catch { }
        Set-QOTStatus "Advanced Error"
    }
}

function Invoke-QOTStartupWarmup {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    try { Write-QLog "Startup warmup: begin" } catch { }

    try { if (Get-Command Test-QOTWingetAvailable -ErrorAction SilentlyContinue) { $null = Test-QOTWingetAvailable } } catch { }
    try { if (Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue) { $null = Get-QOTCommonAppsCatalogue } } catch { }

    try { Write-QLog "Startup warmup: end" } catch { }
}

function Start-QOTMain {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    try {
        try { Write-QLog "Start-QOTMain called. Root = $RootPath" } catch { }

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

        # Start the main window and return the Window object
        $win = Start-QOTMainWindow
        try { $win.Activate() } catch { }

        # Expose the window so Intro.ps1 can wait for it to be visible
        $Global:QOTMainWindow = $win

        return $win
    }
    catch {
        try { Write-QLog "Start-QOTMain failed: $($_.Exception.Message)" "ERROR" } catch { }
        throw
    }
}


Export-ModuleMember -Function `
    Start-QOTMain, `
    Invoke-QOTRun, `
    Invoke-QOTAdvancedRun, `
    Invoke-QOTStartupWarmup, `
    Set-QOTStatus, `
    Set-QOTProgress
