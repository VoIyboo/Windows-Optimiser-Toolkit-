# Config.psm1
# Central configuration for Quinn Optimiser Toolkit

# Holds the current configuration
$script:QOTConfig = $null

function Initialize-QOTConfig {
    param(
        [string]$RootPath
    )

    # If not supplied, auto-detect:
    # Core\Config  -> parent = Core
    # Core         -> parent = src
    # src          -> parent = repo root
    if (-not $RootPath) {
        $RootPath = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
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
        Version  = "2.7.0-core"
    }

    return $script:QOTConfig
}

function Get-QOTConfig {
    if (-not $script:QOTConfig) {
        throw "QOT config has not been initialised. Call Initialize-QOTConfig first."
    }
    return $script:QOTConfig
}

function Get-QOTRoot {
    (Get-QOTConfig).RootPath
}

function Get-QOTPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $cfg = Get-QOTConfig

    switch ($Name.ToLowerInvariant()) {
        "root" { return $cfg.RootPath }
        "src"  { return $cfg.SrcRoot }
        "logs" { return $cfg.LogsRoot }
        default { throw "Unknown QOT path name '$Name'. Valid values: Root, Src, Logs." }
    }
}

function Get-QOTVersion {
    (Get-QOTConfig).Version
}

Export-ModuleMember -Function `
    Initialize-QOTConfig, `
    Get-QOTConfig, `
    Get-QOTRoot, `
    Get-QOTPath, `
    Get-QOTVersion
