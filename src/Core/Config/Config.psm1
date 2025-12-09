# Config.psm1
# Basic configuration for Quinn Optimiser Toolkit

$script:QOTConfig = $null

function Initialize-QOTConfig {
    param(
        [string]$RootPath
    )

    if (-not $RootPath) {
        # Auto-detect: go two levels up from Core\Config to repo root
        $RootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }

    $srcRoot  = Join-Path $RootPath "src"
    $logsRoot = Join-Path $RootPath "Logs"

    if (-not (Test-Path $logsRoot)) {
        New-Item -Path $logsRoot -ItemType Directory -Force | Out-Null
    }

    $script:QOTConfig = [pscustomobject]@{
        RootPath = $RootPath
        SrcRoot  = $srcRoot
        LogsRoot = $logsRoot
    }

    return $script:QOTConfig
}

function Get-QOTConfig {
    if (-not $script:QOTConfig) {
        throw "QOT config has not been initialised. Call Initialize-QOTConfig first."
    }
    return $script:QOTConfig
}

Export-ModuleMember -Function Initialize-QOTConfig, Get-QOTConfig
