# TRASER NuGet Publishing - extracted from TraserBCHelper Push-AppsToNuget

Param(
    [Parameter(Mandatory)][string]$ArtifactsFolder,
    [Parameter(Mandatory)][string]$NuGetToken,
    [string]$ReleaseType = '',
    [switch]$RuntimePackage,
    [string]$RuntimeBCVersion = '',
    [string]$RuntimeValidFor = 'major'
)

if (-not $ReleaseType) { $ReleaseType = Get-ReleaseTypeFromBranch }
Write-Host "Publishing with release type: $ReleaseType"

$appFiles = Get-ChildItem -Path $ArtifactsFolder -Filter *.app -Recurse | Sort-Object Name
foreach ($appFile in $appFiles) {
    $appJson = Get-AppJsonFromAppFile -appFile $appFile.FullName
    $publisher = $appJson.publisher
    $isTraser = ($publisher -eq $TRASERNuGetConfig.TRASERPublisher)

    if ((-not $isTraser) -or $RuntimePackage) {
        $feedUrl = Get-TRASERNuGetFeed -ReleaseType $ReleaseType -Publisher $publisher -RuntimePackage
        if (-not $RuntimeBCVersion) { Write-Error "RuntimeBCVersion required for runtime packages."; continue }
        $runtimeVer = [Version]$RuntimeBCVersion

        # Indirect package
        $indirectId = Get-BcNuGetPackageId -packageIdTemplate "{publisher}.{name}.runtime.{id}" -publisher $publisher -name $appJson.name -id $appJson.id
        $exists = $false; try { $exists = Test-BcNuGetPackage -nuGetServerUrl $feedUrl -nuGetToken $NuGetToken -packageName $indirectId -version $appJson.version -select Exact } catch {}
        if (-not $exists) {
            $appAppVer = [Version]$appJson.Application
            $fromVer = [Version]::new($appAppVer.Major, $appAppVer.Minor, 0, 0)
            $pkg = New-BcNuGetPackage -appfile $appFile.FullName -isIndirectPackage -packageId "{publisher}.{name}.runtime.{id}" -dependencyIdTemplate "{publisher}.{name}.runtime.{id}" -applicationDependency $fromVer
            Push-BcNuGetPackage -nuGetServerUrl $feedUrl -nuGetToken $NuGetToken -bcNuGetPackage $pkg
            Remove-Item $pkg -Force -ErrorAction SilentlyContinue
            Write-Host "Published indirect: $indirectId"
        }

        # Version-specific package
        $versionId = Get-BcNuGetPackageId -packageIdTemplate "{publisher}.{name}.runtime-{version}" -publisher $publisher -name $appJson.name -version $appJson.version
        $exists = $false; try { $exists = Test-BcNuGetPackage -nuGetServerUrl $feedUrl -nuGetToken $NuGetToken -packageName $versionId -version $runtimeVer -select Exact } catch {}
        if (-not $exists) {
            switch ($RuntimeValidFor) {
                'major' { $appDep = "[$($runtimeVer.Major).$($runtimeVer.Minor),$($runtimeVer.Major + 1).0)" }
                'minor' { $appDep = "[$($runtimeVer.Major).$($runtimeVer.Minor),$($runtimeVer.Major).$($runtimeVer.Minor + 1))" }
            }
            $platDep = "[$($runtimeVer.Major).0,$($runtimeVer.Major + 1).0)"
            $pkg = New-BcNuGetPackage -appfile $appFile.FullName -packageId "{publisher}.{name}.runtime-{version}" -dependencyIdTemplate "{publisher}.{name}.runtime.{id}" -packageVersion $runtimeVer -applicationDependency $appDep -platformDependency $platDep
            Push-BcNuGetPackage -nuGetServerUrl $feedUrl -nuGetToken $NuGetToken -bcNuGetPackage $pkg
            Remove-Item $pkg -Force -ErrorAction SilentlyContinue
            Write-Host "Published version-specific: $versionId"
        }
    } else {
        $feedUrl = Get-TRASERNuGetFeed -ReleaseType $ReleaseType -Publisher $publisher
        $packageName = Get-BcNuGetPackageId -publisher $publisher -name $appJson.name -id $appJson.id -version $appJson.version
        $exists = $false; try { $exists = Test-BcNuGetPackage -nuGetServerUrl $feedUrl -nuGetToken $NuGetToken -packageName $packageName -version $appJson.version -select Exact } catch {}
        if ($exists) { Write-Host "Skipping $($appJson.name) $($appJson.version) - exists"; continue }

        if ($ReleaseType -eq 'release') {
            $appAppVer = [Version]$appJson.Application
            $appDep = "[$($appAppVer.Major).$($appAppVer.Minor),$($appAppVer.Major + 3).0)"
            $pkg = New-BcNuGetPackage -appfile $appFile.FullName -applicationDependency $appDep
        } else {
            $pkg = New-BcNuGetPackage -appfile $appFile.FullName
        }
        Push-BcNuGetPackage -nuGetServerUrl $feedUrl -nuGetToken $NuGetToken -bcNuGetPackage $pkg
        Remove-Item $pkg -Force -ErrorAction SilentlyContinue
        Write-Host "Published $($appJson.name) $($appJson.version) to $ReleaseType"
    }
}
