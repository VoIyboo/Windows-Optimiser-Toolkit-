# src\Tickets\Tickets.psm1

$ErrorActionPreference = "Stop"

$toolkitRoot = Split-Path -Parent $PSScriptRoot
$coreSettings = Join-Path $toolkitRoot "Core\Settings.psm1"
$coreTickets = Join-Path $toolkitRoot "Core\Tickets.psm1"

if (-not (Test-Path -LiteralPath $coreSettings)) {
    throw "Tickets wrapper: missing Core Settings module: $coreSettings"
}

if (-not (Test-Path -LiteralPath $coreTickets)) {
    throw "Tickets wrapper: missing Core Tickets module: $coreTickets"
}

Import-Module $coreSettings -Force -ErrorAction Stop
Import-Module $coreTickets -Force -ErrorAction Stop

Export-ModuleMember -Function * -Alias *
