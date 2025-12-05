Import-Module "src\Core\Logging.psm1" -Force
Set-QLogRoot -Root (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs")
Start-QLogSession
Write-QLog "Bootstrap started."

