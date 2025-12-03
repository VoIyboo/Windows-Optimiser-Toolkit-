. "$PSScriptRoot\..\Core\Logging.psm1"

function Register-QMaintenanceTask {
    Write-QLog "Scheduler: register maintenance task (stub)."
}

function Remove-QMaintenanceTask {
    Write-QLog "Scheduler: remove maintenance task (stub)."
}

Export-ModuleMember -Function Register-QMaintenanceTask, Remove-QMaintenanceTask
