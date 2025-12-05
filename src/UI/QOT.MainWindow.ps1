Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$root = Split-Path $PSScriptRoot -Parent

Import-Module (Join-Path $root "Modules\QOT.Common.psm1") -Force

Initialize-QOTCommon
Write-Log "===== Quinn Optimiser Toolkit V3 starting UI ====="

