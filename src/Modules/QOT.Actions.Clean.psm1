# QOT.Actions.Clean.psm1
# Cleaning actions for v2.7 legacy UI

function Action-CleanWindowsUpdateCache   { Write-Log "Clean Windows Update cache (TODO: wire in existing logic)" }
function Action-CleanDeliveryOptimisation { Write-Log "Clean Delivery Optimisation cache (TODO)" }
function Action-ClearTempFolders          { Write-Log "Clear temp folders (TODO)" }
function Action-WinSxSSafeCleanup         { Write-Log "WinSxS safe cleanup (TODO)" }
function Action-RemoveWindowsOld          { Write-Log "Remove Windows.old (TODO)" }
function Action-RemoveOldRestorePoints    { Write-Log "Remove old restore points (TODO)" }
function Action-RemoveDumpsAndLogs        { Write-Log "Remove dumps and logs (TODO)" }

Export-ModuleMember -Function `
    Action-CleanWindowsUpdateCache, `
    Action-CleanDeliveryOptimisation, `
    Action-ClearTempFolders, `
    Action-WinSxSSafeCleanup, `
    Action-RemoveWindowsOld, `
    Action-RemoveOldRestorePoints, `
    Action-RemoveDumpsAndLogs
