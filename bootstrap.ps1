# bootstrap.ps1
# Minimal startup loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Import Config first so paths are available
Import-Module "src\Core\Config\Config.psm1"  -Force

# Prepare folders and base paths
Initialize-QOTConfig

# Import Logging now that folders exist
Import-Module "src\Core\Logging\Logging.psm1" -Force

# Configure logging root under ProgramData
$logRoot = Get-QOTPath -Name Logs
Set-QLogRoot -Root $logRoot

# Start logging session
Start-QLogSession
Write-QLog "Bootstrap initialised. Version: $(Get-QOTVersion)"
Write-QLog "Toolkit root resolved as: $(Get-QOTRoot)"

# ------------------------------------------
# Hand off to Intro.ps1
# ------------------------------------------
$root      = Get-QOTRoot
$introPath = Join-Path $root "src\Intro\Intro.ps1"

if (-not (Test-Path $introPath)) {
    Write-QLog "Intro.ps1 not found at path: $introPath" "ERROR"
    throw "Intro.ps1 not found at path: $introPath"
}

Write-QLog "Launching Intro.ps1 at: $introPath"
& $introPath

Write-QLog "Intro.ps1 completed. Bootstrap exiting."
