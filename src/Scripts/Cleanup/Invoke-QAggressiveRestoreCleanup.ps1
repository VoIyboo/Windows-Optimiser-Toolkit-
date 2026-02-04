param(
    [object]$Window
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1" -Force -ErrorAction Stop

Invoke-QAggressiveRestoreCleanup
