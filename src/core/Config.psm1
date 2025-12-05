# Config.psm1
# Core configuration for Quinn Optimiser Toolkit

# ------------------------------
# Static values
# ------------------------------

# Version of the toolkit
$script:QOT_Version = "2.7.0-core-rebuild"

# Determine repository root based on this file location:
# this file lives in:  <repo>\src\Core\Config.psm1
# we want:             <repo>\
$script:QOT_Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Base data folder under ProgramData
$script:QOT_DataRoot   = Join-Path $env:ProgramData "QuinnOptimiserToolkit"
$script:QOT_LogRoot    = Join-Path $script:QOT_DataRoot "Logs"
$script:QOT_ConfigRoot = Join-Path $script:QOT_DataRoot "Config"
$script:QOT_TempRoot   = Join-Path $env:TEMP "QuinnOptimiserToolkit"


# ------------------------------
# Internal helper
# ------------------------------
function New-QOTDirectoryIfMissing {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}


# ------------------------------
# Public functions
# ------------------------------

function Initialize-QOTConfig {
    <#
        .SYNOPSIS
        Ensures all required folders exist.

        .DESCRIPTION
        Creates the ProgramData data, log and config folders plus
        a temp folder if they do not already exist.
    #>

    New-QOTDirectoryIfMissing -Path $script:QOT_DataRoot
    New-QOTDirectoryIfMissing -Path $script:QOT_LogRoot
    New-QOTDirectoryIfMissing -Path $script:QOT_ConfigRoot
    New-QOTDirectoryIfMissing -Path $script:QOT_TempRoot
}

function Get-QOTVersion {
    <#
        .SYNOPSIS
        Returns the current toolkit version string.
    #>
    return $script:QOT_Version
}

function Get-QOTRoot {
    <#
        .SYNOPSIS
        Returns the root folder of the toolkit repository.
    #>
    return $script:QOT_Root
}

function Get-QOTPath {
    <#
        .SYNOPSIS
        Returns a key path used by the toolkit.

        .PARAMETER Name
        One of: Data, Logs, Config, Temp
    #>

    param(
        [Parameter(Mandatory)]
        [ValidateSet("Data", "Logs", "Config", "Temp")]
        [string]$Name
    )

    switch ($Name) {
        "Data"   { return $script:QOT_DataRoot   }
        "Logs"   { return $script:QOT_LogRoot    }
        "Config" { return $script:QOT_ConfigRoot }
        "Temp"   { return $script:QOT_TempRoot   }
    }
}

# ------------------------------
# Exported members
# ------------------------------
Export-ModuleMember -Function Initialize-QOTConfig, Get-QOTVersion, Get-QOTRoot, Get-QOTPath

