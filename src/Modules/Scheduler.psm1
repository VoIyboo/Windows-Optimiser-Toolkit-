function Register-QMaintenanceTask {
    Write-QLog "Scheduler: task registered."
}

function Remove-QMaintenanceTask {
    Write-QLog "Scheduler: task removed."
}

Export-ModuleMember -Function Register-QMaintenanceTask, Remove-QMaintenanceTask
