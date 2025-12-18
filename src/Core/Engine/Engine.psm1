# Engine.psm1
# Coordinates major operations by calling the feature modules
# Splash is NOT handled here. Intro.ps1 owns creating the splash.
# MainWindow.UI.psm1 handles "Ready", wait 2s, fade, close when SplashWindow is passed.

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
Import-Module "$PSScriptRoot\..\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1"      -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\..\Advanced\NetworkAndServices\NetworkAndServices.psm1"  -Force -ErrorAction SilentlyContinue

function Set-QOTStatus {
    param([string]$Text)

    try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "STATUS: $Text" } } catch { }

    if (Get-Command Set-QOTSummary -ErrorAction SilentlyContinue) {
        Set-QOTSummary -Text $Text
    }
}

function Set-QOTProgress {
    param([int]$Percent)
    try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Progress: $Percent%" } } catch { }
}

function Invoke-QOTRun {
    try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Starting full run" } } catch { }
    Set-QOTStatus "Running..."
    Set-QOTProgress 0

    try {
        if (Get-Command Start-QOTCleaning -ErrorAction SilentlyContinue) { Start-QOTCleaning }
        Set-QOTProgress 33

        if (Get-Command Start-QOTTweaks -ErrorAction SilentlyContinue) { Start-QOTTweaks }
        Set-QOTProgress 66

        try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Run completed" } } catch { }
        Set-QOTProgress 100
        Set-QOTStatus "Completed"
    }
    catch {
        try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Error during run: $($_.Exception.Message)" "ERROR" } } catch { }
        Set-QOTStatus "Error occurred"
    }
}

function Invoke-QOTAdvancedRun {
    try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Starting Advanced run" } } catch { }
    Set-QOTStatus "Running Advanced Tasks..."

    try {
        if (Get-Command Start-QOTAdvancedCleaning -ErrorAction SilentlyContinue) { Start-QOTAdvancedCleaning }
        if (Get-Command Start-QOTNetworkFix -ErrorAction SilentlyContinue) { Start-QOTNetworkFix }

        try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Advanced run completed" } } catch { }
        Set-QOTStatus "Advanced Completed"
    }
    catch {
        try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Error in advanced run: $($_.Exception.Message)" "ERROR" } } catch { }
        Set-QOTStatus "Advanced Error"
    }
}

function Invoke-QOTStartupWarmup {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Startup warmup: begin" } } catch { }

    try { if (Get-Command Test-QOTWingetAvailable -ErrorAction SilentlyContinue) { $null = Test-QOTWingetAvailable } } catch { }
    try { if (Get-Command Get-QOTCommonAppsCatalogue -ErrorAction SilentlyContinue) { $null = Get-QOTCommonAppsCatalogue } } catch { }

    try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Startup warmup: end" } } catch { }
}

function Start-QOTMain {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory = $false)]
        [System.Windows.Window]$SplashWindow
    )

    try { if (Get-Command Write-QLog -ErrorAction SilentlyContinue) { Write-QLog "Start-QOTMain called. Root = $RootPath" } } catch { }

    $uiModule = Join-Path $PSScriptRoot "..\..\UI\MainWindow.UI.psm1"
    $uiModule = [System.IO.Path]::GetFullPath($uiModule)
    
    if (-not (Test-Path -LiteralPath $uiModule)) {
        throw "UI module file missing: $uiModule"
    }
    
    # Always import UI fresh to avoid stale functions from other modules/sessions
    Import-Module $uiModule -Force -ErrorAction Stop
    
    if (-not (Get-Command Start-QOTMainWindow -ErrorAction SilentlyContinue)) {
        throw "UI module not loaded: Start-QOTMainWindow not found"
    }
    if (-not (Get-Command Initialize-QOTMainWindow -ErrorAction SilentlyContinue)) {
        throw "UI module not loaded: Initialize-QOTMainWindow not found"
    }

    Start-QOTMainWindow -SplashWindow $SplashWindow
}

Export-ModuleMember -Function `
    Start-QOTMain, `
    Invoke-QOTRun, `
    Invoke-QOTAdvancedRun, `
    Invoke-QOTStartupWarmup, `
    Set-QOTStatus, `
    Set-QOTProgress
