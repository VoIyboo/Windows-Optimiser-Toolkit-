# NetworkAndServices.psm1
# Quinn Optimiser Toolkit – Advanced network and services module
# Higher risk network and service tuning actions.

# ------------------------------
# Import core logging
# ------------------------------
Import-Module "$PSScriptRoot\..\..\..\Core\Logging\Logging.psm1" -Force

# ------------------------------
# General network tweaks (DNS / MTU / offloads)
# ------------------------------
function Invoke-QAdvancedNetworkTweaks {
    <#
        Planned behaviour:
        - Apply safe DNS tweaks (eg switch to known reliable resolvers if desired)
        - Adjust MTU / offload settings where it helps stability or performance
        - Only touch adapters that are active and not managed by domain GPO where possible
        - Log every change in detail
    #>
    Write-QLog "Advanced: Network tweaks (DNS / MTU / offloads) – placeholder only, no changes made"
}

# ------------------------------
# Disable IPv6 on non-tunnel adapters
# ------------------------------
function Invoke-QDisableIPv6 {
    <#
        Planned behaviour:
        - Enumerate non-tunnel network adapters
        - Disable IPv6 where it is safe and appropriate
        - Make sure it does not break domain, VPN or corporate networking
        - Log all adapters touched and previous state
    #>
    Write-QLog "Advanced: Disable IPv6 on non-tunnel adapters – placeholder only, no changes made"
}

# ------------------------------
# Disable Teredo / 6to4 tunnels
# ------------------------------
function Invoke-QDisableTeredo {
    <#
        Planned behaviour:
        - Disable Teredo and 6to4 tunnel interfaces
        - Only on supported OS versions
        - Log commands used and results
    #>
    Write-QLog "Advanced: Disable Teredo / 6to4 tunnels – placeholder only, no changes made"
}

# ------------------------------
# Service optimisation (non-essential services)
# ------------------------------
function Invoke-QServiceOptimise {
    <#
        Planned behaviour:
        - Identify non-essential background services that can be safely reduced
        - Apply a conservative profile first (eg set to Manual instead of Disabled)
        - Avoid touching AV, VPN, update and core Windows services
        - Log before/after state per service
    #>
    Write-QLog "Advanced: Service optimisation – placeholder only, no changes made"
}

# ------------------------------
# Search indexing tuning
# ------------------------------
function Invoke-QSearchIndexTune {
    <#
        Planned behaviour:
        - Reduce or disable Windows Search indexing for performance
        - Optionally exclude heavy folders (eg temp, large archives)
        - Keep basic search usable for normal users
    #>
    Write-QLog "Advanced: Search indexing tuning – placeholder only, no changes made"
}

# ------------------------------
# Exported functions
# ------------------------------
Export-ModuleMember -Function `
    Invoke-QAdvancedNetworkTweaks, `
    Invoke-QDisableIPv6, `
    Invoke-QDisableTeredo, `
    Invoke-QServiceOptimise, `
    Invoke-QSearchIndexTune
