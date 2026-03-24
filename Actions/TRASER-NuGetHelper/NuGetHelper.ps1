# TRASER NuGet Helper Functions

$TRASERNuGetConfig = @{
    MasterFeed    = "https://pkgs.dev.azure.com/TRASERSoftwareGmbH/57865e76-6f0b-4dd0-967d-d899bfd89907/_packaging/bc-master/nuget/v3/index.json"
    StagingFeed   = "https://pkgs.dev.azure.com/TRASERSoftwareGmbH/57865e76-6f0b-4dd0-967d-d899bfd89907/_packaging/bc-staging/nuget/v3/index.json"
    ReleaseFeed   = "https://pkgs.dev.azure.com/TRASERSoftwareGmbH/57865e76-6f0b-4dd0-967d-d899bfd89907/_packaging/bc-release/nuget/v3/index.json"
    RuntimeFeed   = "https://pkgs.dev.azure.com/TRASERSoftwareGmbH/57865e76-6f0b-4dd0-967d-d899bfd89907/_packaging/bc-runtime/nuget/v3/index.json"
    AppSourceFeed = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
    TRASERPublisher = "TRASER Software GmbH"
    ForNAVMapping = @{
        "7.0.0.1" = "7.0.0.2350"
        "7.1.0.1" = "7.1.0.2400"
    }
}

function Get-TRASERNuGetFeed {
    param(
        [ValidateSet("master", "staging", "release")][string]$ReleaseType = "master",
        [string]$Publisher = "",
        [switch]$RuntimePackage,
        [switch]$UseAppSourceFeed
    )
    if ($UseAppSourceFeed) { return $TRASERNuGetConfig.AppSourceFeed }
    elseif (($Publisher -ne $TRASERNuGetConfig.TRASERPublisher) -or $RuntimePackage) { return $TRASERNuGetConfig.RuntimeFeed }
    elseif ($ReleaseType -eq "master") { return $TRASERNuGetConfig.MasterFeed }
    elseif ($ReleaseType -eq "staging") { return $TRASERNuGetConfig.StagingFeed }
    elseif ($ReleaseType -eq "release") { return $TRASERNuGetConfig.ReleaseFeed }
    else { throw "No feed found for release type '$ReleaseType' and publisher '$Publisher'" }
}

function Get-TRASERNuGetPackageId {
    param(
        [Parameter(Mandatory)][string]$Publisher,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Id,
        [switch]$RuntimePackage,
        [string]$RuntimeVersion = ""
    )
    $p = $Publisher.Replace(" ", ".").ToLower()
    $n = $Name.Replace(" ", ".").ToLower()
    if ($RuntimePackage) {
        if ($RuntimeVersion) { return "$p.$n.runtime-$RuntimeVersion" }
        return "$p.$n.runtime.$Id"
    }
    return "$p.$n.$Id"
}

function Get-ReleaseTypeFromBranch {
    param([string]$BranchRef = $ENV:GITHUB_REF)
    if ($BranchRef -match "refs/heads/staging") { return "staging" }
    elseif ($BranchRef -match "refs/heads/release/") { return "release" }
    else { return "master" }
}

function Get-ForNAVServiceVersion {
    param([string]$ForNAVCoreVersion)
    if ($TRASERNuGetConfig.ForNAVMapping.ContainsKey($ForNAVCoreVersion)) {
        return $TRASERNuGetConfig.ForNAVMapping[$ForNAVCoreVersion]
    }
    return $null
}
