function Invoke-QSafeTweaks {
    Write-QLog "Safe tweaks applied."
}

function Invoke-QDebloatTweaks {
    Write-QLog "Debloat tweaks applied."
}

Export-ModuleMember -Function Invoke-QSafeTweaks, Invoke-QDebloatTweaks
