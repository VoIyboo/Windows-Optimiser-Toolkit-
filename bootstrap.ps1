# bootstrap.ps1
# Minimal startup loader for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

# Import Config first (so we know all paths)
Import-Module "src\Core\Config.psm1" -Force # Quinn said we'll change this line later

# Prepare folders
Initialize-QOTConfig

# Import Logging now that folders exist
Import-Module "src\Core\Logging.psm1" -Force

# Configure logging root
$logRoot = Get-QOTPath -Name Logs
Set-QLogRoot -Root $logRoot

# Start logging session
Start-QLogSession
Write-QLog "Bootstrap initialised. Version: $(Get-QOTVersion)"
Write-QLog "Toolkit root resolved as: $(Get-QOTRoot)"

# ------------------------------------------------
# PLACEHOLDER:
# Later this will call the Intro splash loader
# ------------------------------------------------

Write-QLog "Bootstrap complete. (Intro screen will load once ready)"
