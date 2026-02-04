param(
    [object]$Window
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Advanced\AdvancedTweaks\AdvancedTweaks.psm1" -Force -ErrorAction Stop

Invoke-QAdvancedDisableBackgroundApps
