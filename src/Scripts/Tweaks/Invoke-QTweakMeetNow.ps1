param(
    [object]$Window
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\..\TweaksAndCleaning\TweaksAndPrivacy\TweaksAndPrivacy.psm1" -Force -ErrorAction Stop

Invoke-QTweakMeetNow
