# src\Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1
# UI wiring for the Advanced tab

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\AdvancedTweaks.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\AdvancedCleaning\AdvancedCleaning.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\NetworkAndServices\NetworkAndServices.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Actions\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue

function Initialize-QOTAdvancedTweaksUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )
    try {
        $actions = @(
            @{ Name = "CbAdvAdobeNetworkBlock"; Label = "Adobe network block"; ActionId = "Invoke-QAdvancedAdobeNetworkBlock" },
            @{ Name = "CbAdvBlockRazerInstalls"; Label = "Block Razer software installs"; ActionId = "Invoke-QAdvancedBlockRazerInstalls" },
            @{ Name = "CbAdvBraveDebloat"; Label = "Brave debloat"; ActionId = "Invoke-QAdvancedBraveDebloat" },
            @{ Name = "CbAdvEdgeDebloat"; Label = "Edge debloat"; ActionId = "Invoke-QAdvancedEdgeDebloat" },
            @{ Name = "CbAdvDisableEdge"; Label = "Disable Edge"; ActionId = "Invoke-QAdvancedDisableEdge" },
            @{ Name = "CbAdvEdgeUninstallable"; Label = "Make Edge uninstallable via Settings"; ActionId = "Invoke-QAdvancedEdgeUninstallable" },
            @{ Name = "CbAdvDisableBackgroundApps"; Label = "Disable background apps"; ActionId = "Invoke-QAdvancedDisableBackgroundApps" },
            @{ Name = "CbAdvDisableFullscreenOptimizations"; Label = "Disable fullscreen optimizations"; ActionId = "Invoke-QAdvancedDisableFullscreenOptimizations" },
            @{ Name = "CbAdvDisableIPv6"; Label = "Disable IPv6"; ActionId = "Invoke-QAdvancedDisableIPv6" },
            @{ Name = "CbAdvDisableTeredo"; Label = "Disable Teredo"; ActionId = "Invoke-QAdvancedDisableTeredo" },
            @{ Name = "CbAdvDisableCopilot"; Label = "Disable Microsoft Copilot"; ActionId = "Invoke-QAdvancedDisableCopilot" },
            @{ Name = "CbAdvDisableStorageSense"; Label = "Disable Storage Sense"; ActionId = "Invoke-QAdvancedDisableStorageSense" },
            @{ Name = "CbAdvDisableNotificationTray"; Label = "Disable notification tray/calendar"; ActionId = "Invoke-QAdvancedDisableNotificationTray" },
            @{ Name = "CbAdvDisplayPerformance"; Label = "Set display for performance"; ActionId = "Invoke-QAdvancedDisplayPerformance" },
            @{ Name = "CbAdvRemoveOldProfiles"; Label = "Remove old profiles"; ActionId = "Invoke-QRemoveOldProfiles" },
            @{ Name = "CbAdvAggressiveRestoreCleanup"; Label = "Aggressive restore/log cleanup"; ActionId = "Invoke-QAggressiveRestoreCleanup" },
            @{ Name = "CbAdvDeepCacheCleanup"; Label = "Deep cache/component store cleanup"; ActionId = "Invoke-QAdvancedDeepCache" },
            @{ Name = "CbAdvNetworkReset"; Label = "Network reset"; ActionId = "Invoke-QNetworkReset" },
            @{ Name = "CbAdvRepairNetworkAdapter"; Label = "Repair network adapter"; ActionId = "Invoke-QRepairAdapter" },
            @{ Name = "CbAdvServiceTuning"; Label = "Service tuning"; ActionId = "Invoke-QServiceTune" }
        )

        $actionsSnapshot = $actions

        Register-QOTActionGroup -Name "Advanced" -GetItems ({
            param($Window)

            $items = @()
            foreach ($action in $actionsSnapshot) {
                $actionName = $action.Name
                $actionLabel = $action.Label
                $actionId = $action.ActionId

                $items += [pscustomobject]@{
                    ActionId = $actionId
                    Label = $actionLabel
                    IsSelected = ({
                        param($window)
                        $control = $window.FindName($actionName)
                        $control -and $control.IsChecked -eq $true
                    }).GetNewClosure()
                }
            }
            return $items
        }).GetNewClosure()
        
        try { Write-QLog "Advanced UI initialised (action registry)." "DEBUG" } catch { }
    }
    catch {
        try { Write-QLog ("Advanced UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

Export-ModuleMember -Function Initialize-QOTAdvancedTweaksUI
