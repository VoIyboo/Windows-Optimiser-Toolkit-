function Invoke-QAppScan {
    Write-QLog "App scan invoked."
    return @()   # empty until real logic added
}

function Invoke-QAppUninstall {
    param($AppName)
    Write-QLog "Uninstall requested for $AppName"
}

function Invoke-QAppInstall {
    param($AppName)
    Write-QLog "Install requested for $AppName"
}

Export-ModuleMember -Function Invoke-QAppScan, Invoke-QAppUninstall, Invoke-QAppInstall
