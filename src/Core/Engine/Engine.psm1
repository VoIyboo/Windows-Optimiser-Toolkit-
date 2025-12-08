<#
    Engine.psm1
    Core engine helpers for the Quinn Optimiser Toolkit.

    Responsibilities:
    - Know where feature areas live on disk
    - Provide helpers to import feature modules
    - Provide a central entry point for the main app
#>

Import-Module "$PSScriptRoot\Config.psm1"  -Force
Import-Module "$PSScriptRoot\Logging.psm1" -Force

function Get-QOTModuleRoot {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Intro', 'UI', 'TweaksAndCleaning', 'Apps', 'Advanced')]
        [string]$Area
    )

    $root = Get-QOTRoot

    switch ($Area) {
        'Intro'             { return Join-Path $root 'src\Intro' }
        'UI'                { return Join-Path $root 'src\UI' }
        'TweaksAndCleaning' { return Join-Path $root 'src\TweaksAndCleaning' }
        'Apps'              { return Join-Path $root 'src\Apps' }
        'Advanced'          { return Join-Path $root 'src\Advanced' }
    }
}

function Import-QOTModule {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [string]$Area
    )

    if ($Area) {
        $folder   = Get-QOTModuleRoot -Area $Area
        $fullPath = Join-Path $folder $RelativePath
    } else {
        $fullPath = Join-Path (Get-QOTRoot) $RelativePath
    }

    if (-not (Test-Path $fullPath)) {
        Write-QLog "Import-QOTModule could not find $fullPath" "WARN"
        return
    }

    Write-QLog "Importing feature module $fullPath"
    Import-Module $fullPath -Force
}

function Initialize-QOTEngine {
    Write-QLog "Initialising engine."
    # Later we can preload modules or run health checks here
}

function Start-QOTMain {
    param(
        [string]$Mode = 'Normal'
    )

    Write-QLog "Start-QOTMain called. Mode: $Mode"

    # Make sure engine is ready
    Initialize-QOTEngine

    # Hand off to the main WPF window
    Write-QLog "Launching main WPF window..."
    Start-QOTMainWindow
    Write-QLog "Main WPF window closed."
}


Export-ModuleMember -Function `
    Get-QOTModuleRoot, `
    Import-QOTModule, `
    Initialize-QOTEngine, `
    Start-QOTMain



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

# Import feature modules so the engine knows about them
Import-Module "$PSScriptRoot\..\TweaksAndCleaning\CleaningAndMain\CleaningAndMain.psm1" -Force
Import-Module "$PSScriptRoot\..\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force
Import-Module "$PSScriptRoot\..\Advanced\AdvancedCleaning\AdvancedCleaning.psm1"       -Force
Import-Module "$PSScriptRoot\..\Advanced\NetworkAndServices\NetworkAndServices.psm1"   -Force
Import-Module "$PSScriptRoot\..\UI\MainWindow.UI.psm1"                                  -Force

function Start-QOTMain {
    param(
        [string]$Mode = 'Normal'
    )

    Write-QLog "Start-QOTMain called. Mode: $Mode"

    # Make sure engine is ready
    Initialize-QOTEngine

    # Try to update the status text in the UI (if loaded)
    try {
        Set-QOTSummary "System ready. Engine initialised."
    } catch { }

    # Open the main window
    try {
        Show-QOTMainWindow
    } catch {
        Write-QLog "Failed to open main window: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Quinn Optimiser Toolkit could not open the main window.`n`n" +
            "Check the log for more details.",
            "Quinn Optimiser Toolkit",
            'OK',
            'Error'
        ) | Out-Null
    }
}
