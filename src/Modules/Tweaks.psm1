. "$PSScriptRoot\..\Core\Logging.psm1"

function Invoke-QSafeTweaks {
    Write-QLog "Safe tweaks applied (stub)."
}

function Invoke-QDebloatTweaks {
    Write-QLog "Debloat tweaks applied (stub)."
}

Export-ModuleMember -Function Invoke-QSafeTweaks, Invoke-QDebloatTweaks
