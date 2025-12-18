# src\Tickets\Tickets.psm1
# Compatibility wrapper for the Tickets engine.
# This module exists so older code that imports src\Tickets\Tickets.psm1
# still works, while the real implementation lives in src\Core.

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Resolve paths
# ------------------------------------------------------------
$toolkitRoot   = Split-Path -Parent $PSScriptRoot
$coreSettings  = Join-Path $toolkitRoot "Core\Settings.psm1"
$coreTickets   = Join-Path $toolkitRoot "Core\Tickets.psm1"

# ------------------------------------------------------------
# Validate files exist
# ------------------------------------------------------------
if (-not (Test-Path -LiteralPath $coreSettings)) {
    throw "Tickets wrapper: missing Core Settings module: $coreSettings"
}

if (-not (Test-Path -LiteralPath $coreTickets)) {
    throw "Tickets wrapper: missing Core Tickets module: $coreTickets"
}

# ------------------------------------------------------------
# Import Core modules
# ------------------------------------------------------------
Import-Module $coreSettings -Force -ErrorAction Stop
Import-Module $coreTickets  -Force -ErrorAction Stop

# ------------------------------------------------------------
# Re-export all public functions from imported modules
# ------------------------------------------------------------
Export-ModuleMember -Function * -Alias *
