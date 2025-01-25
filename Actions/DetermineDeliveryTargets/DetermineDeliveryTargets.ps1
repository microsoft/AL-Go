Param(
    [Parameter(HelpMessage = "Projects to investigate", Mandatory = $false)]
    [string] $projectsJson = '["."]',
    [Parameter(HelpMessage = "Check whether context secret exists?", Mandatory = $false)]
    [bool] $checkContextSecrets
)

function ContinuousDelivery([string] $deliveryTarget, [string[]] $projects) {
    $settingsName = "DeliverTo$deliveryTarget"
    if ($deliveryTarget -eq 'AppSource' -and $settings.type -eq "AppSource App") {
        # For multi-project repositories, ContinuousDelivery can be set on the projects
        foreach($project in $projects) {
            $projectSettings = ReadSettings -project $project
            if ($projectSettings.deliverToAppSource.ContinuousDelivery -or ($projectSettings.Contains('AppSourceContinuousDelivery') -and $projectSettings.AppSourceContinuousDelivery)) {
                Write-Host "Project $project is setup for Continuous Delivery to AppSource"
                return $true
            }
        }
        return $false
    }
    elseif ($settings.Contains($settingsName) -and $settings."$settingsName".Contains('ContinuousDelivery')) {
        return $settings."$settingsName".ContinuousDelivery
    }
    else {
        return $true
    }
}

function IncludeBranch([string] $deliveryTarget) {
    $settingsName = "DeliverTo$deliveryTarget"
    if ($settings.Contains($settingsName) -and $settings."$settingsName".Contains('Branches')) {
        Write-Host "- Branches defined: $($settings."$settingsName".Branches -join ', ')"
        return ($null -ne ($settings."$settingsName".Branches | Where-Object { $ENV:GITHUB_REF_NAME -like $_ }))
    }
    else {
        Write-Host "- No branches defined, defaulting to main"
        return ($ENV:GITHUB_REF_NAME -eq 'main')
    }
}

function IncludeDeliveryTarget([string] $deliveryTarget, [string[]] $projects) {
    Write-Host "DeliveryTarget $_"
    # DeliveryTarget Context Secret needs to be specified for a delivery target to be included
    $contextName = "$($_)Context"
    $secrets = $env:Secrets | ConvertFrom-Json
    if (-not $secrets."$contextName") {
        Write-Host "- Secret '$contextName' not found"
        return $false
    }
    return (IncludeBranch -deliveryTarget $deliveryTarget) -and (ContinuousDelivery -deliveryTarget $deliveryTarget -projects $projects)
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
$deliveryTargets = @('GitHubPackages','NuGet','Storage')
if ($settings.type -eq "AppSource App") {
    $deliveryTargets += @("AppSource")
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
    $projects = $projectsJson | ConvertFrom-Json
    $deliveryTargets = @($deliveryTargets | Where-Object { IncludeDeliveryTarget -deliveryTarget $_ -projects $projects })
}
$contextSecrets = @($deliveryTargets | ForEach-Object { "$($_)Context" })

#region Action: Output
$deliveryTargetsJson = ConvertTo-Json -InputObject $deliveryTargets -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DeliveryTargetsJson=$deliveryTargetsJson"
Write-Host "DeliveryTargetsJson=$deliveryTargetsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ContextSecrets=$($contextSecrets -join ',')"
Write-Host "ContextSecrets=$($contextSecrets -join ',')"
#endregion
