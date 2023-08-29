Param(
    [Parameter(HelpMessage = "Projects to investigate", Mandatory = $false)]
    [string] $projectsJson = '["."]',
    [Parameter(HelpMessage = "Check whether context secret exists", Mandatory = $false)]
    [bool] $checkContextSecrets
)

function IncludeBranch([string] $deliveryTarget) {
    $settingsName = "DeliverTo$deliveryTarget"
    if ($settings.Contains($settingsName) -and $settings."$settingsName".Contains('Branches')) {
        Write-Host "- Branches defined: $($settings."$settingsName".Branches -join ', ') - "
        return ($null -ne ($settings."$settingsName".Branches | Where-Object { $ENV:GITHUB_REF_NAME -like $_ }))
    }
    else {
        Write-Host "- No branches defined, defaulting to main"
        return ($ENV:GITHUB_REF_NAME -eq 'main')
    }
}

function IncludeDeliveryTarget([string] $deliveryTarget) {
    Write-Host "DeliveryTarget $_ - "
    # DeliveryTarget Context Secret needs to be specified for a delivery target to be included
    $contextName = "$($_)Context"
    $secrets = $env:Secrets | ConvertFrom-Json
    if (-not $secrets."$contextName") {
        Write-Host "- Secret '$contextName' not found"
        return $false
    }
    return (IncludeBranch -deliveryTarget $deliveryTarget)
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
$deliveryTargets = @('GitHubPackages','NuGet','Storage')
if ($settings.type -eq "AppSource App") {
    # For multi-project repositories, we will add deliveryTarget AppSource if any project has AppSourceContinuousDelivery set to true
    ($projectsJson | ConvertFrom-Json) | ForEach-Object {
        $projectSettings = ReadSettings -project $_
        if ($projectSettings.Contains('AppSourceContinuousDelivery') -and $projectSettings.AppSourceContinuousDelivery) {
            Write-Host "Project $_ is setup for Continuous Delivery"
            $deliveryTargets += @("AppSource")
        }
    }
}
# Include custom delivery targets
$namePrefix = 'DeliverTo'
Get-Item -Path (Join-Path $ENV:GITHUB_WORKSPACE ".github/$($namePrefix)*.ps1") | ForEach-Object {
    $deliveryTarget = [System.IO.Path]::GetFileNameWithoutExtension($_.Name.SubString($namePrefix.Length))
    $deliveryTargets += @($deliveryTarget)
}
$deliveryTargets = @($deliveryTargets | Select-Object -unique)
if ($checkContextSecrets) {
    # Check all delivery targets and include only the ones needed
    $deliveryTargets = @($deliveryTargets | Where-Object { IncludeDeliveryTarget -deliveryTarget $_ })
}
$contextSecrets = @($deliveryTargets | ForEach-Object { "$($_)Context" })

#region Action: Output
$deliveryTargetsJson = ConvertTo-Json -InputObject $deliveryTargets -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DeliveryTargetsJson=$deliveryTargetsJson"
Write-Host "DeliveryTargetsJson=$deliveryTargetsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ContextSecrets=$($contextSecrets -join ',')"
Write-Host "ContextSecrets=$($contextSecrets -join ',')"
#endregion
