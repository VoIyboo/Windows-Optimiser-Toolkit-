param(
    [object]$Window
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Advanced\NetworkAndServices\NetworkAndServices.psm1" -Force -ErrorAction Stop

Invoke-QRepairAdapter
