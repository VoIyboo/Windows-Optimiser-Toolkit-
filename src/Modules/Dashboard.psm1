function Get-QSystemHealth {
    Write-QLog "System health check."
    return @{
        CPU = "0%"
        RAM = "0%"
        Disk = "0%"
    }
}

Export-ModuleMember -Function Get-QSystemHealth
