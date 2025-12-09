# Config.psm1
# Basic configuration for Quinn Optimiser Toolkit

# We keep a single config object in script scope
$script:QOTConfig = $null

function Initialize-QOTConfig {
    param(
        [string]$RootPath
    )

    # If no root path is supplied, assume:
    # this file = src\Core\Config
    # parent    = src\Core
    # parent    = src
    if (-not $RootPath) {
        $coreFolder = Split-Path $PSScriptRoot -Parent
        $RootPath   = Split-Path $coreFolder -Parent
    }

    # Default logs root under ProgramData
    $logsRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
    if (-not (Test-Path $logsRoot)) {
        New-Item -Path $logsRoot -ItemType Directory -Force | Out-Null
    }

    $script:QOTConfig = [PSCustomObject]@{
        RootPath = $RootPath
        LogsRoot = $logsRoot
        Version  = "2.7"
    }

    return $script:QOTConfig
}

function Get-QOTConfig {
    if (-not $script:QOTConfig) {
        Initialize-QOTConfig | Out-Null
    }
    return $script:QOTConfig
}

function Get-QOTPaths {
    # For now this is just an alias-style helper that returns the same object
    if (-not $script:QOTConfig) {
        Initialize-QOTConfig | Out-Null
    }
    return $script:QOTConfig
}

function Get-QOTVersion {
    if ($script:QOTConfig -and $script:QOTConfig.Version) {
        return $script:QOTConfig.Version
    }
    return "2.7"
}

Export-ModuleMember -Function Initialize-QOTConfig, Get-QOTConfig, Get-QOTPaths, Get-QOTVersion
