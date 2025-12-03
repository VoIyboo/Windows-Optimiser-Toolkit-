function Get-QStartupItems {
    return @()
}

function Set-QStartupItem {
    param($Item, $Enabled)
    Write-QLog "Startup item change: $Item -> $Enabled"
}

Export-ModuleMember -Function Get-QStartupItems, Set-QStartupItem
