. (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)

<#
.SYNOPSIS
Get projects in dependency order for delivery

.DESCRIPTION
Retrieves projects from the repository and returns them sorted in dependency order,
ensuring that base projects are delivered before dependent projects.

.PARAMETER BaseFolder
The base folder of the repository

.PARAMETER ProjectsFromSettings
Projects specified in settings

.PARAMETER SelectProjects
Projects to select (supports wildcards, default is "*" for all projects)

.OUTPUTS
Array of project paths sorted by dependency order
#>
function Get-ProjectsInDeliveryOrder {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $BaseFolder,

        [Parameter(Mandatory = $false)]
        [string[]] $ProjectsFromSettings = @(),

        [Parameter(Mandatory = $false)]
        [string] $SelectProjects = "*"
    )

    # Get the list of projects from the repository
    $projectList = @(GetProjectsFromRepository -baseFolder $BaseFolder -projectsFromSettings $ProjectsFromSettings -selectProjects $SelectProjects)

    if ($projectList.Count -eq 0) {
        return @()
    }

    if ($projectList.Count -eq 1) {
        return $projectList
    }

    # Analyze project dependencies to determine build order
    $projectBuildInfo = AnalyzeProjectDependencies -baseFolder $BaseFolder -projects $projectList

    # Flatten the build order into a single sorted list
    $sortedProjectList = @()
    foreach($buildOrder in $projectBuildInfo.FullProjectsOrder) {
        $sortedProjectList += $buildOrder.projects
    }

    return $sortedProjectList
}

<#
.SYNOPSIS
Add an entry for a delivered app package to the delivery manifest

.DESCRIPTION
Adds an entry describing a delivered app package to the delivery manifest collection.
Only production apps (apps originating from the Apps artifact folder) which have actually
been pushed to the delivery target are added to the manifest. Test apps, dependencies and
packages which were not pushed (because the exact version already existed on the feed, because
the latest package was identical to the app being delivered or because the push failed) are
never added to the manifest.

.PARAMETER Manifest
The delivery manifest collected so far

.PARAMETER ArtifactType
The type of the artifact folder the app was delivered from (Apps, TestApps or Dependencies)

.PARAMETER Pushed
Whether the package was actually pushed to the delivery target

.PARAMETER AppJson
The app.json content of the app which was delivered

.PARAMETER Project
The AL-Go project the app was delivered from

.PARAMETER PackageName
The name of the NuGet package which was pushed

.PARAMETER DeliveryTarget
The delivery target the package was pushed to (default is NuGet)

.OUTPUTS
The delivery manifest including the new entry (if the entry qualifies for the manifest)

.EXAMPLE
$deliveryManifest = Add-DeliveryManifestEntry -Manifest $deliveryManifest -ArtifactType 'Apps' -Pushed $true -AppJson $appJson -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.<guid>'
#>
function Add-DeliveryManifestEntry {
    Param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]] $Manifest = @(),

        [Parameter(Mandatory = $true)]
        [string] $ArtifactType,

        [Parameter(Mandatory = $true)]
        [bool] $Pushed,

        [Parameter(Mandatory = $true)]
        [object] $AppJson,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Project = '',

        [Parameter(Mandatory = $true)]
        [string] $PackageName,

        [Parameter(Mandatory = $false)]
        [string] $DeliveryTarget = 'NuGet'
    )

    $manifestEntries = @($Manifest)

    # Only packages which were actually pushed to the delivery target are part of the manifest
    if (-not $Pushed) {
        Write-Output -NoEnumerate $manifestEntries
        return
    }

    # Only production apps (from the Apps artifact folder) are part of the manifest
    if ($ArtifactType -ne 'Apps') {
        Write-Output -NoEnumerate $manifestEntries
        return
    }

    $manifestEntries += [PSCustomObject]@{
        "id"             = "$($AppJson.id)"
        "name"           = "$($AppJson.name)"
        "publisher"      = "$($AppJson.publisher)"
        "version"        = "$($AppJson.version)"
        "project"        = "$Project"
        "packageName"    = "$PackageName"
        "deliveryTarget" = "$DeliveryTarget"
    }

    Write-Output -NoEnumerate $manifestEntries
}

<#
.SYNOPSIS
Save the delivery manifest as a JSON file

.DESCRIPTION
Writes the delivery manifest to a JSON file using a versioned envelope containing GitHub run
provenance. The apps property is always written as a JSON array, including when no packages were delivered.

.PARAMETER Manifest
The delivery manifest to save

.PARAMETER Path
The path of the JSON file to write

.OUTPUTS
The path of the JSON file which was written

.EXAMPLE
$manifestPath = Save-DeliveryManifest -Manifest $deliveryManifest -Path (Join-Path $ENV:RUNNER_TEMP 'DeliveryManifest-NuGet.json')
#>
function Save-DeliveryManifest {
    Param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]] $Manifest = @(),

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $manifestEntries = @($Manifest)

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    $deliveryManifest = [PSCustomObject]@{
        "schemaVersion"  = 1
        "repository"     = "$ENV:GITHUB_REPOSITORY"
        "runId"          = "$ENV:GITHUB_RUN_ID"
        "runAttempt"     = "$ENV:GITHUB_RUN_ATTEMPT"
        "headSha"        = "$ENV:GITHUB_SHA"
        "deliveryTarget" = "NuGet"
        "apps"           = [object[]] $manifestEntries
    }
    $json = ConvertTo-Json -InputObject $deliveryManifest -Depth 10

    Set-Content -Path $Path -Value $json -Encoding UTF8
    return $Path
}

<#
.SYNOPSIS
Normalizes the app.json of an app file for comparison with a previously published package

.DESCRIPTION
The revision of the app version is generated for every build, so it is removed before comparing.
Everything else in app.json, including major, minor and build of the version, is compared: when it changes,
the new package must be delivered, even when the code is unchanged.

.PARAMETER AppJson
The app.json object generated from the app file

.OUTPUTS
The normalized app.json as a JSON string
#>
function ConvertTo-ComparableAppJson {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $AppJson
    )

    $comparable = $AppJson | ConvertTo-Json -Depth 99 | ConvertFrom-Json
    if (($comparable.PSObject.Properties.Name -contains 'version') -and $comparable.version) {
        $version = [System.Version] "$($comparable.version)"
        $comparable.version = "$($version.Major).$($version.Minor).$([Math]::Max($version.Build, 0))"
    }
    return $comparable | ConvertTo-Json -Depth 99
}

Export-ModuleMember -Function Get-ProjectsInDeliveryOrder, Add-DeliveryManifestEntry, Save-DeliveryManifest, ConvertTo-ComparableAppJson
