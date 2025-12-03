# Engine.psm1
# Responsible for starting the correct engine / legacy version

function Start-QOTLegacy {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $legacyPath = Join-Path $RootPath "src\Legacy\QuinnOptimiserToolkit-v2.7.ps1"

    if (-not (Test-Path $legacyPath)) {
        Write-QLog "Legacy script not found at $legacyPath" "ERROR"
        throw "Legacy toolkit (v2.7) script not found."
    }

    Write-QLog "Starting legacy toolkit from $legacyPath"

    # Run the v2.7 script in the current process
    & $legacyPath
}

Export-ModuleMember -Function Start-QOTLegacy
