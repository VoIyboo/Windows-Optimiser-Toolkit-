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

    # Placeholder for now
    # Intro will later call this and then hand off to the WPF main window
}

Export-ModuleMember -Function `
    Get-QOTModuleRoot, `
    Import-QOTModule, `
    Initialize-QOTEngine, `
    Start-QOTMain

