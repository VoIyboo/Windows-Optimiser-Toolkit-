param(
    [object]$Window
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\CleaningAndMain\Cleaning.psm1" -Force -ErrorAction Stop

Invoke-QCleanWindowsUpdateCache
