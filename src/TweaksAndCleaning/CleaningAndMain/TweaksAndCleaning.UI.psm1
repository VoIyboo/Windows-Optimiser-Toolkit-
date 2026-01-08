# src\TweaksAndCleaning\TweaksAndCleaning.UI.psm1
# UI wiring for the Tweaks & Cleaning tab

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\Core\Config\Config.psm1"   -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Logging\Logging.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\..\Core\Actions\ActionRegistry.psm1" -Force -ErrorAction SilentlyContinue

Import-Module "$PSScriptRoot\Cleaning.psm1"                          -Force -ErrorAction Stop
Import-Module "$PSScriptRoot\..\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force -ErrorAction Stop

function Invoke-QOTAction {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Label
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        try { Write-QLog ("Tweaks/Cleaning action not found: {0}" -f $Name) "ERROR" } catch { }
        return $false
    }

    try {
        & $cmd
        return $true
    }
    catch {
        try { Write-QLog ("Tweaks/Cleaning action failed ({0}): {1}" -f $Label, $_.Exception.Message) "ERROR" } catch { }
        return $false
    }
}

function Get-QOTNamedElement {
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Root -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    try {
        $q = New-Object 'System.Collections.Generic.Queue[System.Windows.DependencyObject]'
        $q.Enqueue($Root) | Out-Null

        while ($q.Count -gt 0) {
            $cur = $q.Dequeue()
            if ($cur -is [System.Windows.FrameworkElement]) {
                if ($cur.Name -eq $Name) {
                    return $cur
                }
            }

            $count = 0
            try { $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($cur) } catch { $count = 0 }
            for ($i = 0; $i -lt $count; $i++) {
                try {
                    $child = [System.Windows.Media.VisualTreeHelper]::GetChild($cur, $i)
                    if ($child) { $q.Enqueue($child) | Out-Null }
                } catch { }
            }
        }
    }
    catch { }

    return $null
}



function Initialize-QOTTweaksAndCleaningUI {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window
    )

    try {
        $runButton = $Window.FindName("RunButton")
        if (-not $runButton) {
            try { Write-QLog "Tweaks/Cleaning UI: RunButton not found in XAML (x:Name='RunButton')." "ERROR" } catch { }
            return
        }

        $actions = @(
            @{ Name = "CbCleanTempFiles";       Label = "Clear temporary files";                 Command = "Invoke-QCleanTemp" },
            @{ Name = "CbEmptyRecycleBin";      Label = "Empty Recycle Bin";                      Command = "Invoke-QCleanRecycleBin" },
            @{ Name = "CbCleanDoCache";         Label = "Clean Delivery Optimisation cache";      Command = "Invoke-QCleanDOCache" },
            @{ Name = "CbCleanWuCache";         Label = "Clear Windows Update cache";             Command = "Invoke-QCleanWindowsUpdateCache" },
            @{ Name = "CbCleanThumbCache";      Label = "Clean thumbnail cache";                  Command = "Invoke-QCleanThumbnailCache" },
            @{ Name = "CbCleanErrorLogs";       Label = "Clean old error logs and crash dumps";   Command = "Invoke-QCleanErrorLogs" },
            @{ Name = "CbCleanSetupLeftovers";  Label = "Remove safe setup / upgrade leftovers";  Command = "Invoke-QCleanSetupLeftovers" },
            @{ Name = "CbClearStoreCache";      Label = "Clear Microsoft Store cache";            Command = "Invoke-QCleanStoreCache" },
            @{ Name = "CbEdgeLightCleanup";     Label = "Light clean of Microsoft Edge cache";    Command = "Invoke-QCleanEdgeCache" },
            @{ Name = "CbChromeLightCleanup";   Label = "Light clean of Chrome / Chromium cache"; Command = "Invoke-QCleanChromeCache" },
            @{ Name = "CbDisableStartRecommended"; Label = "Hide Start menu recommended items";   Command = "Invoke-QTweakStartMenuRecommendations" },
            @{ Name = "CbDisableSuggestedApps";    Label = "Turn off suggested apps and promotions"; Command = "Invoke-QTweakSuggestedApps" },
            @{ Name = "CbDisableTipsStart";        Label = "Disable tips and suggestions in Start"; Command = "Invoke-QTweakTipsInStart" },
            @{ Name = "CbDisableBingSearch";       Label = "Turn off Bing / web results in Start search"; Command = "Invoke-QTweakBingSearch" },
            @{ Name = "CbClassicMoreOptions";      Label = "Use classic 'More options' right-click menu"; Command = "Invoke-QTweakClassicContextMenu" },
            @{ Name = "CbDisableWidgets";          Label = "Turn off Widgets";                    Command = "Invoke-QTweakWidgets" },
            @{ Name = "CbDisableTaskbarNews";      Label = "Turn off News / taskbar content";      Command = "Invoke-QTweakNewsAndInterests" },
            @{ Name = "CbDisableMeetNow";          Label = "Hide legacy Meet Now button";          Command = "Invoke-QTweakMeetNow" },
            @{ Name = "CbDisableAdvertisingId";    Label = "Turn off advertising ID";              Command = "Invoke-QTweakAdvertisingId" },
            @{ Name = "CbLimitFeedbackPrompts";    Label = "Reduce feedback and survey prompts";   Command = "Invoke-QTweakFeedbackHub" },
            @{ Name = "CbDisableOnlineTips";       Label = "Disable online tips and suggestions";  Command = "Invoke-QTweakOnlineTips" }
        )
        
        Register-QOTActionGroup -Name "Tweaks & Cleaning" -GetItems {
            param([System.Windows.Window]$Window)

            $items = @()
            foreach ($action in $actions) {
                $actionRef = $action
                $items += @{
                    Label = $actionRef.Label
                    IsSelected = {
                        param($window)
                        $control = Get-QOTNamedElement -Root $window -Name $actionRef.Name
                        $control -and $control.IsChecked -eq $true
                    }
                    Execute = { param($window) Invoke-QOTAction -Name $actionRef.Command -Label $actionRef.Label | Out-Null }
                }

            }
            return $items
        }

        try { Write-QLog "Tweaks & Cleaning UI initialised (action registry)." "DEBUG" } catch { }

}
    }
    catch {
        try { Write-QLog ("Tweaks/Cleaning UI initialisation error: {0}" -f $_.Exception.Message) "ERROR" } catch { }
    }
}

Export-ModuleMember -Function Initialize-QOTTweaksAndCleaningUI
