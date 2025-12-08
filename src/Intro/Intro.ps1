# Intro.ps1
# Entry point used after bootstrap to start the Quinn Optimiser Toolkit

param(
    [string]$Mode = "Normal"
)

$ErrorActionPreference = "Stop"

# ------------------------------
# Load core modules
# ------------------------------
Import-Module "$PSScriptRoot\..\Core\Config.psm1"  -Force
Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force
Import-Module "$PSScriptRoot\..\Core\Engine.psm1"  -Force
# Later we will also import the splash UI here
# Import-Module "$PSScriptRoot\Splash.UI.psm1" -Force

# ------------------------------
# Ensure config + logging are ready
# ------------------------------
Initialize-QOTConfig

$logRoot = Get-QOTPath -Name Logs
Set-QLogRoot -Root $logRoot
Start-QLogSession

Write-QLog "Intro started. Mode: $Mode"

# ------------------------------
# Hand off to the engine
# ------------------------------
try {
    Write-QLog "Initialising engine from Intro."
    Initialize-QOTEngine

    # Later: show splash + main WPF window here.
    # For now we just call Start-QOTMain so the wiring is in place.
    Write-QLog "Calling Start-QOTMain from Intro."
    Start-QOTMain -Mode $Mode

    Write-QLog "Intro completed successfully."
}
catch {
    Write-QLog "Intro failed: $($_.Exception.Message)" "ERROR"
    throw
}
