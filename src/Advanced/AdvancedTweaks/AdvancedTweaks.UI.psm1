# src\Advanced\AdvancedTweaks\AdvancedTweaks.UI.psm1
# UI wiring for the Advanced tab

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\AdvancedTweaks.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Actions\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue

function Invoke-QOTAdvancedAction {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Label
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        try { Write-QLog ("Advanced action not found: {0}" -f $Name) "ERROR" } catch { }
        return $false
    }

    try {
        & $cmd
        return $true
    }
    catch {
        try { Write-QLog ("Advanced action failed ({0}): {1}" -f $Label, $_.Exception.Message) "ERROR" } catch { }
        return $false
    }
}

function Initialize-QOTAdvancedTweaksUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    try {
        $runButton = $Window.FindName("RunButton")
        if (-not $runButton) {
            try { Write-QLog "Advanced UI: RunButton not found in XAML (x:Name='RunButton')." "ERROR" } catch { }
            return
        }

        $actions = @(
            @{ Name = "CbAdvAdobeNetworkBlock"; Label = "Adobe network block"; Command = "Invoke-QAdvancedAdobeNetworkBlock" },
            @{ Name = "CbAdvBlockRazerInstalls"; Label = "Block Razer software installs"; Command = "Invoke-QAdvancedBlockRazerInstalls" },
            @{ Name = "CbAdvBraveDebloat"; Label = "Brave debloat"; Command = "Invoke-QAdvancedBraveDebloat" },
            @{ Name = "CbAdvEdgeDebloat"; Label = "Edge debloat"; Command = "Invoke-QAdvancedEdgeDebloat" },
            @{ Name = "CbAdvDisableEdge"; Label = "Disable Edge"; Command = "Invoke-QAdvancedDisableEdge" },
            @{ Name = "CbAdvEdgeUninstallable"; Label = "Make Edge uninstallable via Settings"; Command = "Invoke-QAdvancedEdgeUninstallable" },
            @{ Name = "CbAdvDisableBackgroundApps"; Label = "Disable background apps"; Command = "Invoke-QAdvancedDisableBackgroundApps" },
            @{ Name = "CbAdvDisableFullscreenOptimizations"; Label = "Disable fullscreen optimizations"; Command = "Invoke-QAdvancedDisableFullscreenOptimizations" },
            @{ Name = "CbAdvDisableIPv6"; Label = "Disable IPv6"; Command = "Invoke-QAdvancedDisableIPv6" },
            @{ Name = "CbAdvDisableTeredo"; Label = "Disable Teredo"; Command = "Invoke-QAdvancedDisableTeredo" },
            @{ Name = "CbAdvDisableCopilot"; Label = "Disable Microsoft Copilot"; Command = "Invoke-QAdvancedDisableCopilot" },
            @{ Name = "CbAdvDisableStorageSense"; Label = "Disable Storage Sense"; Command = "Invoke-QAdvancedDisableStorageSense" },
            @{ Name = "CbAdvDisableNotificationTray"; Label = "Disable notification tray/calendar"; Command = "Invoke-QAdvancedDisableNotificationTray" },
            @{ Name = "CbAdvDisplayPerformance"; Label = "Set display for performance"; Command = "Invoke-QAdvancedDisplayPerformance" }
        )

        Register-QOTActionGroup -Name "Advanced" -GetItems {
            param([System.Windows.Window]$Window)

            $items = @()
            foreach ($action in $actions) {
                $actionRef = $action
                $items += @{
                    Label = $actionRef.Label
                    IsSelected = {
                        param($window)
                        $control = $window.FindName($actionRef.Name)
                        $control -and $control.IsChecked -eq $true
                    }
                    Execute = { param($window) Invoke-QOTAdvancedAction -Name $actionRef.Command -Label $actionRef.Label | Out-Null }
                }

            return $items
        }

        try { Write-QLog "Advanced UI initialised (action registry)." "DEBUG" } catch { }
    }
    catch {
        try { Write-QLog ("Advanced UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

Export-ModuleMember -Function Initialize-QOTAdvancedTweaksUI
