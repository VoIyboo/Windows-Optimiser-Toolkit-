param(
    [Parameter(Mandatory)]
    [object]$Window
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Apps\Apps.Actions.psm1" -Force -ErrorAction Stop

$appsGrid = $Window.FindName("AppsGrid")
$installGrid = $Window.FindName("InstallGrid")
$statusLabel = $Window.FindName("StatusLabel")

if (-not $appsGrid -or -not $installGrid) {
    throw "Apps grids not available for Apps.RunSelected."
}

Invoke-QOTRunSelectedAppsActions -Window $Window -AppsGrid $appsGrid -InstallGrid $installGrid -StatusLabel $statusLabel
