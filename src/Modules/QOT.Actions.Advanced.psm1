# QOT.Actions.Advanced.psm1
# Advanced / risky optimisation actions

function Action-RemoveOldProfiles         { Write-Log "Remove old user profiles (TODO)" }
function Action-AdvancedRestoreAggressive { Write-Log "Aggressive restore point / log cleanup (TODO)" }
function Action-AdvancedDeepCache         { Write-Log "Deep cache cleanup (component store etc) (TODO)" }
function Action-AdvancedNetworkTweaks     { Write-Log "General network tweaks (TODO)" }
function Action-DisableIPv6               { Write-Log "Disable IPv6 on non tunnel adapters (TODO)" }
function Action-DisableTeredo             { Write-Log "Disable Teredo / 6to4 (TODO)" }
function Action-AdvancedServiceOptimise   { Write-Log "Service tuning / disabling non essential services (TODO)" }
function Action-AdvancedSearchIndex       { Write-Log "Reduce or disable Windows Search indexing (TODO)" }

Export-ModuleMember -Function `
    Action-RemoveOldProfiles, `
    Action-AdvancedRestoreAggressive, `
    Action-AdvancedDeepCache, `
    Action-AdvancedNetworkTweaks, `
    Action-DisableIPv6, `
    Action-DisableTeredo, `
    Action-AdvancedServiceOptimise, `
    Action-AdvancedSearchIndex

