. "$PSScriptRoot\..\Core\Logging.psm1"

function Get-QStartupItems {
    Write-QLog "Startup items requested (stub)."

    @(
        [pscustomobject]@{
            Name     = "Example Startup"
            Location = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
            Enabled  = $true
            Risk     = "Green"
        }
    )
}

function Set-QStartupItem {
    param(
        [string]$Name,
        [bool]$Enabled
    )
    Write-QLog "Startup change: $Name -> Enabled=$Enabled (stub)."
}

Export-ModuleMember -Function Get-QStartupItems, Set-QStartupItem
