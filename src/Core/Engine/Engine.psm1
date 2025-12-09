# Engine.psm1
# Coordinates major operations by calling the feature modules

Import-Module "$PSScriptRoot\..\Config\Config.psm1"  -Force
Import-Module "$PSScriptRoot\..\Logging\Logging.psm1" -Force

# Import feature modules (corrected file names + folders)
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\CleaningAndMain\Cleaning.psm1" -Force
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force

Import-Module "$PSScriptRoot\..\..\Apps\InstalledApps\InstalledApps.psm1" -Force
Import-Module "$PSScriptRoot\..\..\Apps\InstallCommonApps\InstallCommonApps.psm1" -Force

Import-Module "$PSScriptRoot\..\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1" -Force
Import-Module "$PSScriptRoot\..\..\Advanced\NetworkAndServices\NetworkAndServices.psm1" -Force


# ------------------------------------------------------------
# Small helpers used by the UI
# ------------------------------------------------------------

function Set-QOTStatus {
    param([string]$Text)

    Write-QLog "STATUS: $Text"

    if (Get-Command Set-QOTSummary -ErrorAction SilentlyContinue) {
        Set-QOTSummary -Text $Text
    }
}

function Set-QOTProgress {
    param([int]$Percent)

    Write-QLog "Progress: $Percent%"
}

# ------------------------------------------------------------
# Run button logic
# ------------------------------------------------------------

function Invoke-QOTRun {
    Write-QLog "Starting full run"
    Set-QOTStatus "Running…"
    Set-QOTProgress 0

    try {
        Start-QOTCleaning
        Set-QOTProgress 33

        Start-QOTTweaks
        Set-QOTProgress 66

        # Placeholder for future expansion
        Write-QLog "Run completed"
        Set-QOTProgress 100
        Set-QOTStatus "Completed"
    }
    catch {
        Write-QLog "Error during run: $($_.Exception.Message)" "ERROR"
        Set-QOTStatus "Error occurred"
    }
}

# ------------------------------------------------------------
# Advanced Run
# ------------------------------------------------------------

function Invoke-QOTAdvancedRun {
    Write-QLog "Starting *Advanced* run"
    Set-QOTStatus "Running Advanced Tasks…"

    try {
        Start-QOTAdvancedCleaning
        Start-QOTNetworkFix

        Write-QLog "Advanced run completed"
        Set-QOTStatus "Advanced Completed"
    }
    catch {
        Write-QLog "Error in advanced run: $($_.Exception.Message)" "ERROR"
        Set-QOTStatus "Advanced Error"
    }
}

# ------------------------------------------------------------
# Start-QOTMain: entry point for main UI
# ------------------------------------------------------------

function Start-QOTMain {
    param(
        [string]$RootPath
    )

    Write-QLog "Start-QOTMain called. Root = $RootPath"

    if (-not (Get-Command Start-QOTMainWindow -ErrorAction SilentlyContinue)) {
        throw "UI module not loaded: Start-QOTMainWindow not found"
    }

    try {
        Start-QOTMainWindow
    }
    catch {
        Write-QLog "UI failed to start: $($_.Exception.Message)" "ERROR"
        throw
    }
}

Export-ModuleMember -Function `
    Start-QOTMain, `
    Invoke-QOTRun, `
    Invoke-QOTAdvancedRun, `
    Set-QOTStatus, `
    Set-QOTProgress
