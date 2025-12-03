. "$PSScriptRoot\..\Core\Logging.psm1"

function Invoke-QAppScan {
    Write-QLog "App scan invoked (stub)."

    @(
        [pscustomobject]@{
            Name      = "Example App"
            Publisher = "Quinn Labs"
            SizeMB    = 123
            Risk      = "Green"
        }
    )
}

function Invoke-QAppUninstall {
    param([string]$AppName)
    Write-QLog "Uninstall requested for $AppName (stub)."
}

function Invoke-QAppInstall {
    param([string]$AppName)
    Write-QLog "Install requested for $AppName (stub)."
}

Export-ModuleMember -Function Invoke-QAppScan, Invoke-QAppUninstall, Invoke-QAppInstall
