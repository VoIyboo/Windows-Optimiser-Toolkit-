# Engine.psm1

function Invoke-QAction {
    param([string]$ActionName)

    Write-QLog "Action triggered: $ActionName"
}

Export-ModuleMember -Function Invoke-QAction
