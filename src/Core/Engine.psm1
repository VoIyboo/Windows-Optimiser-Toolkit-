# Engine.psm1

. "$PSScriptRoot\Logging.psm1"

function Invoke-QAction {
    param(
        [Parameter(Mandatory)]
        [string]$ActionName,
        [hashtable]$Parameters
    )

    Write-QLog "QAction invoked: $ActionName"
    # Later this can become a central dispatcher
}

Export-ModuleMember -Function Invoke-QAction
