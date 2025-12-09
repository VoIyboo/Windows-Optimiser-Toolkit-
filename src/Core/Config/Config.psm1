# Config.psm1
# Core configuration and path helpers for the Quinn Optimiser Toolkit

# These live only inside this module
$script:QOTRoot    = $null
$script:QOTVersion = "2.7.0"

# -----------------------------
# Root handling
# -----------------------------

function Set-QOTRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $script:QOTRoot = $Path
}

function Get-QOTRoot {

    if ($script:QOTRoot) {
        return $script:QOTRoot
    }

    # If bootstrap set a global root, prefer that
    if ($Global:QOT_Root) {
        $script:QOTRoot = $Global:QOT_Root
        return $script:QOTRoot
    }

    # Fallback: walk up from src\Core\Config
    $configDir = $PSScriptRoot                     # ...\src\Core\Config
    $coreDir   = Split-Path $configDir -Parent     # ...\src\Core
    $srcDir    = Split-Path $coreDir   -Parent     # ...\src
    $rootDir   = Split-Path $srcDir    -Parent     # repo root

    $script:QOTRoot = $rootDir
    return $script:QOTRoot
}

function Get-QOTVersion {
    return $script:QOTVersion
}

# -----------------------------
# Path helper
# -----------------------------

function Get-QOTPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $root = Get-QOTRoot

    switch ($Name.ToLowerInvariant()) {
        'root'        { return $root }
        'logs'        { return (Join-Path $root "Logs") }
        'src'         { return (Join-Path $root "src") }
        'core'        { return (Join-Path $root "src\Core") }
        'intro'       { return (Join-Path $root "src\Intro") }
        'ui'          { return (Join-Path $root "src\UI") }
        'cleaning'    { return (Join-Path $root "src\TweaksAndCleaning\CleaningAndMain") }
        'tweaks'      { return (Join-Path $root "src\TweaksAndCleaning\TweaksAndPrivacy") }
        'apps'        { return (Join-Path $root "src\Apps") }
        'advanced'    { return (Join-Path $root "src\Advanced") }
        default       { return (Join-Path $root $Name) }
    }
}

# -----------------------------
# Initialisation
# -----------------------------

function Initialize-QOTConfig {

    # Make sure root is resolved
    [void](Get-QOTRoot)

    # Ensure key folders exist
    $paths = @(
        Get-QOTPath -Name 'Logs'
    )

    foreach ($p in $paths) {
        if (-not (Test-Path $p)) {
            New-Item -Path $p -ItemType Directory -Force | Out-Null
        }
    }
}

# -----------------------------
# Exports
# -----------------------------

Export-ModuleMember -Function `
    Set-QOTRoot, `
    Get-QOTRoot, `
    Get-QOTVersion, `
    Get-QOTPath, `
    Initialize-QOTConfig
