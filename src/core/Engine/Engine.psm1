





# ==========================================================
# Tweaks, Cleaning and Advanced – engine dispatch scaffolding
# ==========================================================

# Import feature modules so the engine knows about them
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\CleaningAndMain\CleaningAndMain.psm1"    -Force
Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1"  -Force
Import-Module "$PSScriptRoot\..\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1"          -Force
Import-Module "$PSScriptRoot\..\..\Advanced\NetworkAndServices\NetworkAndServices.psm1"      -Force

function Invoke-QOTCleaningRun {
    <#
        High level entry point for Cleaning & Maintenance.

        Later this will:
        - Accept options or a profile from the UI
        - Call into CleaningAndMain.psm1 functions
        - Update status / progress

        Right now it just logs that it was called.
    #>
    param(
        [string]$Profile = "Basic"
    )

    Write-QLog "Engine: Cleaning run requested. Profile = '$Profile' (placeholder only, no actions wired yet)"
}

function Invoke-QOTTweaksRun {
    <#
        High level entry point for Tweaks & Privacy.

        Later this will:
        - Accept flags from the UI (UI tweaks, privacy tweaks, etc)
        - Call into TweaksAndPrivacy.psm1 functions

        For now it only logs.
    #>
    param(
        [string]$Profile = "Custom"
    )

    Write-QLog "Engine: Tweaks run requested. Profile = '$Profile' (placeholder only, no actions wired yet)"
}

function Invoke-QOTAdvancedRun {
    <#
        High level entry point for Advanced tab.

        Later this will:
        - Decide which advanced cleaning + network + service actions to run
        - Call functions from AdvancedCleaning.psm1 and NetworkAndServices.psm1

        For now it only logs.
    #>
    param(
        [switch]$DoCleaning,
        [switch]$DoNetwork,
        [switch]$DoServices
    )

    $flags = @()
    if ($DoCleaning) { $flags += "Cleaning" }
    if ($DoNetwork)  { $flags += "Network"  }
    if ($DoServices) { $flags += "Services" }

    if ($flags.Count -eq 0) {
        Write-QLog "Engine: Advanced run requested with no flags – placeholder, doing nothing"
    } else {
        $joined = $flags -join ", "
        Write-QLog "Engine: Advanced run requested for: $joined (placeholder only, no actions wired yet)"
    }
}

# If you already have an Export-ModuleMember above, you can either:
# - add these names to it, OR
# - use a second Export-ModuleMember like this.

Export-ModuleMember -Function `
    Invoke-QOTCleaningRun, `
    Invoke-QOTTweaksRun, `
    Invoke-QOTAdvancedRun
