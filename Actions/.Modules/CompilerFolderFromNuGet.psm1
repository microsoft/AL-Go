<#
    Builds a compiler folder from Microsoft's public NuGet feeds instead of from a
    Business Central artifact.

    The folder layout produced here is deliberately identical to the one
    New-BcCompilerFolder (BcContainerHelper) produces, so that everything downstream
    - Get-ALTool, Get-CustomAnalyzers, Get-AssemblyProbingPaths, Build-AppsInWorkspace -
    keeps working unchanged:

        <compilerFolder>/compiler/extension/bin/   alc, altool and the built-in analyzers
        <compilerFolder>/symbols/*.app            System.app + the app dependency closure

    Two feeds are involved:
      - MSSymbols (Azure DevOps, public): symbol-only .app packages for the Microsoft
        platform and application, per country. A full closure is ~7 MB.
      - nuget.org: Microsoft.Dynamics.BusinessCentral.Development.Tools.<Platform>,
        which carries alc/altool plus CodeCop, AppSourceCop, PerTenantExtensionCop and
        UICop for the running OS.

    Compared with downloading the artifact this moves ~2.2 GB of zips off the critical
    path. See Scenarios/SymbolsFromNuGet.md for the measurements.

    NOTE: this module must stay PowerShell 5 compatible - AL-Go still runs PS5 on
    windows-latest runners. No ternary operators, no ?? operator, no ForEach-Object
    -Parallel, no Start-ThreadJob.
#>

$script:MSSymbolsFeedUrl = 'https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json'
$script:NuGetOrgFlatContainerUrl = 'https://api.nuget.org/v3-flatcontainer'

# Publisher name Microsoft uses on the MSSymbols feed
$script:MicrosoftPublisher = 'Microsoft'

<#
.SYNOPSIS
    Returns true when running on Windows, in a way that is safe on PowerShell 5.
#>
function Test-OnWindows {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # PowerShell 5 only ships on Windows
        return $true
    }
    return $IsWindows
}

<#
.SYNOPSIS
    Returns the AL compiler package name to pull from nuget.org.
.DESCRIPTION
    The framework-dependent package is used rather than the platform-specific
    .Linux/.Win/.Osx ones: 15.7 MB against 58 MB, which measured ~4 seconds of
    difference on the critical path. It carries alc.dll/altool.dll plus all four
    built-in analyzers; Add-ALToolLaunchers supplies the launcher the platform
    packages would have provided.
#>
function Get-ALCompilerPackageName {
    return 'Microsoft.Dynamics.BusinessCentral.Development.Tools'
}

<#
.SYNOPSIS
    Makes the AL tools in a bin folder directly executable on the current OS.
.DESCRIPTION
    The generic Development.Tools package is framework-dependent: it carries alc.dll and
    altool.dll plus Windows apphosts (alc.exe/altool.exe), but no native launcher for
    Linux or macOS. It is 15.7 MB against 58 MB for the platform-specific packages, and
    that difference is ~4 seconds on the critical path, so it is worth keeping.

    Rather than teaching Get-ALTool and CompileAppsInWorkspace to launch through 'dotnet'
    - which would mean changing the shared compile path - this writes a small shell
    wrapper next to the dll. Get-ALTool then finds 'altool' exactly as it does with an
    artifact-provided vsix, and nothing downstream changes.
.PARAMETER BinFolder
    The compiler/extension/bin folder.
#>
function Add-ALToolLaunchers {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BinFolder
    )

    if (Test-OnWindows) {
        # alc.exe / altool.exe are already in the package
        return
    }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "The .NET runtime is required to run the AL compiler from NuGet, but 'dotnet' was not found on the PATH."
    }

    foreach ($tool in @('alc', 'altool')) {
        $dll = Join-Path $BinFolder "$tool.dll"
        if (-not (Test-Path $dll)) {
            continue
        }
        $launcher = Join-Path $BinFolder $tool
        # Resolve the dll relative to the launcher so the folder stays relocatable
        $content = "#!/bin/sh`nexec dotnet `"`$(dirname `"`$0`")/$tool.dll`" `"`$@`"`n"
        [System.IO.File]::WriteAllText($launcher, $content)
        & chmod +x $launcher
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to make $launcher executable"
        }
    }
}

<#
.SYNOPSIS
    Picks the symbols package version that corresponds to a Business Central artifact version.
.DESCRIPTION
    Artifact versions and symbol package versions agree on major.minor.build but not on
    the revision - the revision is a separate counter on each side, and the symbol
    revision can be either higher or lower than the artifact's. Verified against every
    sandbox artifact version from 26.0 onwards (1076 versions): all of them resolve on
    the first three segments, none resolve on all four reliably.

    So: filter to versions sharing major.minor.build, take the highest revision.
.PARAMETER Versions
    All versions available for the package.
.PARAMETER ArtifactVersion
    The four-part version from the resolved artifact URL.
.OUTPUTS
    The matching version string, or $null when the feed has nothing for that build.
#>
function Select-BcSymbolsVersion {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Versions,
        [Parameter(Mandatory = $true)]
        [string] $ArtifactVersion
    )

    $parts = $ArtifactVersion.Split('.')
    if ($parts.Count -lt 3) {
        throw "'$ArtifactVersion' is not a valid Business Central artifact version"
    }
    $prefix = "$($parts[0]).$($parts[1]).$($parts[2])."

    $candidates = @($Versions | Where-Object { $_ -and $_.StartsWith($prefix) })
    if ($candidates.Count -eq 0) {
        return $null
    }

    # Sort numerically on the revision rather than as strings, so 100 sorts after 99
    $sorted = @($candidates | Sort-Object -Property @{ Expression = { [int]($_.Split('.')[3]) } })
    return $sorted[$sorted.Count - 1]
}

<#
.SYNOPSIS
    Resolves the flat container (PackageBaseAddress) URL of a NuGet v3 feed.
.PARAMETER FeedIndexUrl
    URL of the feed's index.json.
#>
function Get-NuGetFlatContainerUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FeedIndexUrl
    )

    $index = Invoke-RestMethod -Uri $FeedIndexUrl -UseBasicParsing
    $resource = @($index.resources | Where-Object { $_.'@type' -eq 'PackageBaseAddress/3.0.0' })
    if ($resource.Count -eq 0) {
        throw "NuGet feed '$FeedIndexUrl' does not expose a PackageBaseAddress/3.0.0 resource"
    }
    return $resource[0].'@id'.TrimEnd('/')
}

<#
.SYNOPSIS
    Lists the available versions of a package on a NuGet v3 flat container.
.OUTPUTS
    Array of version strings. Empty when the package does not exist on the feed.
#>
function Get-NuGetPackageVersions {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FlatContainerUrl,
        [Parameter(Mandatory = $true)]
        [string] $PackageId
    )

    $url = "$FlatContainerUrl/$($PackageId.ToLowerInvariant())/index.json"
    try {
        $response = Invoke-RestMethod -Uri $url -UseBasicParsing
    }
    catch {
        return @()
    }
    if (-not $response.versions) {
        return @()
    }
    return @($response.versions)
}

<#
.SYNOPSIS
    Fetches the version list for several packages concurrently.
.DESCRIPTION
    Every version lookup is an HTTPS round trip to Azure DevOps, and doing them one after
    another dominated the first implementation. PowerShell 5 has no ForEach-Object
    -Parallel, so this uses HttpClient tasks.
.PARAMETER PackageIds
    Package ids to look up.
.OUTPUTS
    Hashtable keyed by lower-cased package id, each value an array of version strings.
    Packages missing from the feed map to an empty array.
#>
function Get-NuGetPackageVersionsInParallel {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FlatContainerUrl,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $PackageIds
    )

    $result = @{}
    if ($PackageIds.Count -eq 0) {
        return $result
    }

    Add-Type -AssemblyName System.Net.Http | Out-Null
    $httpClient = New-Object System.Net.Http.HttpClient
    $httpClient.Timeout = [System.TimeSpan]::FromMinutes(2)
    $httpClient.DefaultRequestHeaders.Add('User-Agent', 'AL-Go')
    try {
        $tasks = @()
        foreach ($packageId in $PackageIds) {
            $id = $packageId.ToLowerInvariant()
            if ($result.ContainsKey($id)) {
                continue
            }
            $result[$id] = @()
            $tasks += , @{
                Id   = $id
                Task = $httpClient.GetStringAsync("$FlatContainerUrl/$id/index.json")
            }
        }
        foreach ($entry in $tasks) {
            try {
                $json = $entry.Task.GetAwaiter().GetResult() | ConvertFrom-Json
                if ($json.versions) {
                    $result[$entry.Id] = @($json.versions)
                }
            }
            catch {
                # A package that is not on the feed is not an error here - the caller decides
                $result[$entry.Id] = @()
            }
        }
    }
    finally {
        $httpClient.Dispose()
    }
    return $result
}

<#
.SYNOPSIS
    Downloads a set of files concurrently.
.DESCRIPTION
    Uses HttpClient tasks rather than Start-ThreadJob or ForEach-Object -Parallel so
    that this works on PowerShell 5 as well as 7.
.PARAMETER Downloads
    Array of hashtables with Url and File keys.
#>
function Get-FilesInParallel {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable[]] $Downloads
    )

    if ($Downloads.Count -eq 0) {
        return
    }

    Add-Type -AssemblyName System.Net.Http | Out-Null
    $httpClient = New-Object System.Net.Http.HttpClient
    $httpClient.Timeout = [System.TimeSpan]::FromMinutes(10)
    $httpClient.DefaultRequestHeaders.Add('User-Agent', 'AL-Go')
    try {
        $tasks = @()
        foreach ($download in $Downloads) {
            $folder = [System.IO.Path]::GetDirectoryName($download.File)
            if (-not (Test-Path $folder)) {
                New-Item $folder -ItemType Directory -Force | Out-Null
            }
            $tasks += , @{
                Task = $httpClient.GetByteArrayAsync($download.Url)
                File = $download.File
                Url  = $download.Url
            }
        }
        foreach ($entry in $tasks) {
            try {
                $bytes = $entry.Task.GetAwaiter().GetResult()
            }
            catch {
                throw "Failed to download '$($entry.Url)': $($_.Exception.Message)"
            }
            [System.IO.File]::WriteAllBytes($entry.File, $bytes)
        }
    }
    finally {
        $httpClient.Dispose()
    }
}

<#
.SYNOPSIS
    Reads the dependency ids declared in a .nupkg's nuspec.
.OUTPUTS
    Array of package ids. Empty when the package declares no dependencies.
#>
function Get-NuGetPackageDependencies {
    param(
        [Parameter(Mandatory = $true)]
        [string] $PackageFile
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    $zip = [System.IO.Compression.ZipFile]::OpenRead($PackageFile)
    try {
        $entry = @($zip.Entries | Where-Object { $_.Name -like '*.nuspec' })
        if ($entry.Count -eq 0) {
            return @()
        }
        $stream = $entry[0].Open()
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            $nuspec = [xml]$reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }

    $dependencies = @()
    if ($nuspec.package.metadata.dependencies) {
        foreach ($dependency in @($nuspec.package.metadata.dependencies.dependency)) {
            if ($dependency -and $dependency.id) {
                $dependencies += $dependency.id
            }
        }
    }
    return $dependencies
}

<#
.SYNOPSIS
    Extracts every .app file from a .nupkg into a folder.
.OUTPUTS
    Number of .app files extracted.
#>
function Expand-AppsFromNuGetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $PackageFile,
        [Parameter(Mandatory = $true)]
        [string] $DestinationFolder
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    $count = 0
    $zip = [System.IO.Compression.ZipFile]::OpenRead($PackageFile)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.Name -like '*.app') {
                $target = Join-Path $DestinationFolder $entry.Name
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
                $count++
            }
        }
    }
    finally {
        $zip.Dispose()
    }
    return $count
}

<#
.SYNOPSIS
    Picks the highest version satisfying a NuGet interval range such as [28.4.0.0,28.5.0.0).
.DESCRIPTION
    Only the interval forms NuGet uses in Business Central symbol packages are supported:
    inclusive/exclusive lower and upper bounds, and a bare version meaning "at least".
.PARAMETER Versions
    Available versions.
.PARAMETER Range
    The range expression from the nuspec dependency.
.OUTPUTS
    The selected version string, or $null when nothing satisfies the range.
#>
function Select-NuGetVersionInRange {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Versions,
        [Parameter(Mandatory = $true)]
        [string] $Range
    )

    $stable = @($Versions | Where-Object { $_ -and ($_ -notlike '*-*') })
    if ($stable.Count -eq 0) {
        return $null
    }

    $trimmed = $Range.Trim()
    if ($trimmed -notmatch '^[\[\(]') {
        # A bare version means "this version or higher"
        $minVersion = [System.Version]$trimmed
        $matching = @($stable | Where-Object { ([System.Version]$_) -ge $minVersion })
    }
    else {
        $lowerInclusive = $trimmed.StartsWith('[')
        $upperInclusive = $trimmed.EndsWith(']')
        $inner = $trimmed.Substring(1, $trimmed.Length - 2)
        $bounds = $inner.Split(',')
        $lower = $bounds[0].Trim()
        $upper = ''
        if ($bounds.Count -gt 1) {
            $upper = $bounds[1].Trim()
        }

        $matching = @($stable | Where-Object {
                $version = [System.Version]$_
                $ok = $true
                if ($lower) {
                    if ($lowerInclusive) { $ok = $ok -and ($version -ge [System.Version]$lower) }
                    else { $ok = $ok -and ($version -gt [System.Version]$lower) }
                }
                if ($ok -and $upper) {
                    if ($upperInclusive) { $ok = $ok -and ($version -le [System.Version]$upper) }
                    else { $ok = $ok -and ($version -lt [System.Version]$upper) }
                }
                $ok
            })
    }

    if ($matching.Count -eq 0) {
        return $null
    }
    $sorted = @($matching | Sort-Object -Property @{ Expression = { [System.Version]$_ } })
    return $sorted[$sorted.Count - 1]
}

<#
.SYNOPSIS
    Picks the AL compiler version to use for a Business Central version.
.DESCRIPTION
    AL major = Business Central major - 11 (BC 27 -> AL 16, BC 28 -> AL 17, BC 29 -> AL 18).

    Policies mirror the existing vsixFile setting:
      default  - newest stable of the matching AL major, falling back to that major's
                 newest prerelease when Microsoft has published no stable yet (which is
                 the normal state for a BC major still in preview)
      latest   - newest stable across all majors
      preview  - newest version across all majors, including prereleases
.PARAMETER Versions
    All versions available for the compiler package.
.PARAMETER BcVersion
    The Business Central version being built for.
.PARAMETER Policy
    default, latest or preview.
#>
function Select-ALCompilerVersion {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Versions,
        [Parameter(Mandatory = $true)]
        [string] $BcVersion,
        [Parameter(Mandatory = $false)]
        [ValidateSet('default', 'latest', 'preview')]
        [string] $Policy = 'default'
    )

    if ($Versions.Count -eq 0) {
        throw "No AL compiler versions available on nuget.org"
    }

    $sortVersion = { [System.Version](($_ -split '-')[0]) }
    $stable = @($Versions | Where-Object { $_ -notlike '*-*' })

    if ($Policy -eq 'preview') {
        $sorted = @($Versions | Sort-Object -Property @{ Expression = $sortVersion })
        return $sorted[$sorted.Count - 1]
    }
    if ($Policy -eq 'latest') {
        if ($stable.Count -eq 0) {
            throw "No stable AL compiler version available on nuget.org"
        }
        $sorted = @($stable | Sort-Object -Property @{ Expression = $sortVersion })
        return $sorted[$sorted.Count - 1]
    }

    $bcMajor = [int](($BcVersion -split '\.')[0])
    $alMajor = $bcMajor - 11
    $inMajor = @($stable | Where-Object { $_.StartsWith("$alMajor.") })
    if ($inMajor.Count -eq 0) {
        # A BC major still in preview has no stable compiler yet - fall back to prerelease
        $inMajor = @($Versions | Where-Object { $_.StartsWith("$alMajor.") })
        if ($inMajor.Count -eq 0) {
            throw "No AL compiler version found for AL major $alMajor (Business Central $BcVersion). Set vsixFile to 'latest' to use the newest compiler instead."
        }
        Write-Host "::Notice::No stable AL $alMajor compiler published yet; using the newest prerelease"
    }
    $sorted = @($inMajor | Sort-Object -Property @{ Expression = $sortVersion })
    return $sorted[$sorted.Count - 1]
}

<#
.SYNOPSIS
    Returns the name of the application symbols package for a country.
.DESCRIPTION
    w1 has no country suffix on the MSSymbols feed; every other country does, uppercased.
#>
function Get-BcApplicationSymbolsPackageName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Country
    )

    if ($Country -eq 'w1' -or $Country -eq '') {
        return 'Microsoft.Application.symbols'
    }
    return "Microsoft.Application.$($Country.ToUpperInvariant()).symbols"
}

<#
.SYNOPSIS
    Builds the MSSymbols package name for a Microsoft app dependency.
.DESCRIPTION
    Microsoft publishes one symbols package per app per country, named

        Microsoft.<AppNameWithoutSpaces>[.<COUNTRY>].symbols.<appId>

    with the country segment omitted for w1, matching the application package. Verified
    against the feed for Test Runner, Library Assert, Library Variable Storage,
    Permissions Mock, Application Test Library, Business Foundation Test Libraries and
    Error Messages with Recommendations.

    Both halves come straight out of the dependency entry in app.json, so this resolves
    any Microsoft dependency an app declares - not a curated list of the ones we thought
    of. That is the part New-BcCompilerFolder gets wrong: it copies test libraries out of
    the artifact by filename glob, which breaks whenever Microsoft moves or renames one.
.PARAMETER Name
    The dependency's name, as declared in app.json.
.PARAMETER Id
    The dependency's app id.
.PARAMETER Country
    Localization of the build.
#>
function Get-BcSymbolsPackageNameForDependency {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Id,
        [Parameter(Mandatory = $true)]
        [string] $Country
    )

    $segment = $Name -replace ' ', ''
    if ($Country -eq 'w1' -or $Country -eq '') {
        return "Microsoft.$segment.symbols.$Id"
    }
    return "Microsoft.$segment.$($Country.ToUpperInvariant()).symbols.$Id"
}

<#
.SYNOPSIS
    Collects the Microsoft app dependencies declared by a set of app folders.
.DESCRIPTION
    Only dependencies published by Microsoft are returned - everything else is resolved
    by AL-Go's existing dependency handling (appDependencyProbingPaths, project
    dependencies, trusted NuGet feeds) and copied into the symbols folder separately.

    The Application and Platform dependencies are implicit in every app and are already
    staged from the application symbols package, so they are not returned here.
.PARAMETER AppFolders
    Absolute paths of folders containing an app.json.
.PARAMETER Country
    Localization of the build.
.OUTPUTS
    Array of MSSymbols package ids.
#>
function Get-MicrosoftDependencyPackages {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $AppFolders,
        [Parameter(Mandatory = $true)]
        [string] $Country
    )

    $packages = @()
    foreach ($appFolder in $AppFolders) {
        $appJsonFile = Join-Path $appFolder 'app.json'
        if (-not (Test-Path $appJsonFile)) {
            continue
        }
        $appJson = Get-Content -Path $appJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($appJson.PSObject.Properties.Name -notcontains 'dependencies') {
            continue
        }
        foreach ($dependency in @($appJson.dependencies)) {
            if (-not $dependency) {
                continue
            }
            # app.json has used both casings for these properties over the years
            $publisher = ''
            foreach ($key in @('publisher', 'Publisher')) {
                if ($dependency.PSObject.Properties.Name -contains $key) { $publisher = "$($dependency.$key)" }
            }
            if ($publisher -ne $script:MicrosoftPublisher) {
                continue
            }
            $name = ''
            foreach ($key in @('name', 'Name')) {
                if ($dependency.PSObject.Properties.Name -contains $key) { $name = "$($dependency.$key)" }
            }
            $id = ''
            foreach ($key in @('id', 'appId', 'Id', 'AppId')) {
                if ($dependency.PSObject.Properties.Name -contains $key) { $id = "$($dependency.$key)" }
            }
            if ((-not $name) -or (-not $id)) {
                continue
            }
            $packages += Get-BcSymbolsPackageNameForDependency -Name $name -Id $id -Country $Country
        }
    }
    return @($packages | Select-Object -Unique)
}

<#
.SYNOPSIS
    Throws when a project cannot be built with symbols from NuGet.
.DESCRIPTION
    Microsoft's NuGet feeds carry symbol packages but no service tier assemblies, so the
    compiler folder has no dlls folder and no assembly probing paths. That only matters
    for apps using .NET interop, which Business Central permits only for apps targeting
    OnPrem or Internal. Those must keep building from the artifact.

    A vsixFile pointing at a specific download URL likewise has no NuGet equivalent.
.PARAMETER Settings
    The project settings, containing appFolders, testFolders, bcptTestFolders and vsixFile.
.PARAMETER ProjectFolder
    Folder the app folders are relative to.
#>
function Test-SymbolsFromNuGetSupported {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Settings,
        [Parameter(Mandatory = $true)]
        [string] $ProjectFolder
    )

    if ($Settings.vsixFile -like 'https://*' -or $Settings.vsixFile -like 'http://*') {
        throw "symbolsSource is set to 'nuGet', which cannot be combined with a vsixFile download URL. Set vsixFile to 'default', 'latest' or 'preview', or set symbolsSource to 'artifact'."
    }

    $folders = @()
    foreach ($key in @('appFolders', 'testFolders', 'bcptTestFolders')) {
        if ($Settings.Keys -contains $key) {
            $folders += @($Settings."$key")
        }
    }

    foreach ($folder in $folders) {
        $appJsonFile = Join-Path (Join-Path $ProjectFolder $folder) 'app.json'
        if (-not (Test-Path $appJsonFile)) {
            continue
        }
        $appJson = Get-Content -Path $appJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $target = ''
        if ($appJson.PSObject.Properties.Name -contains 'target') {
            $target = "$($appJson.target)"
        }
        if ($target -eq 'OnPrem' -or $target -eq 'Internal') {
            throw "App '$folder' has target '$target', which may use .NET interop. Symbols from NuGet do not include the service tier assemblies needed for that. Set symbolsSource to 'artifact' for this project."
        }
    }
}

<#
.SYNOPSIS
    Creates a compiler folder populated from Microsoft's public NuGet feeds.
.DESCRIPTION
    Produces the same folder layout as New-BcCompilerFolder, without downloading any
    Business Central artifact. See the module header for the layout and the rationale.

    Only the symbols an app actually needs are staged: the closure declared by the
    application symbols package, plus whatever Microsoft dependencies the apps being
    compiled declare in their app.json (the test toolkit, for a test app).
.PARAMETER ArtifactUrl
    The resolved artifact URL. Used only to derive the Business Central version and
    country; nothing is downloaded from it.
.PARAMETER CompilerFolder
    Folder to create. Removed first when it already exists.
.PARAMETER VsixFile
    The vsixFile setting: '', 'default', 'latest' or 'preview'. A direct URL is not
    supported here and must fall back to the artifact path.
.PARAMETER AppFolders
    Absolute paths of the app folders being compiled. Their app.json dependencies decide
    which Microsoft symbol packages are staged, so a test app pulls the test toolkit and
    nothing else pulls it.
.OUTPUTS
    The path to the created compiler folder.
#>
function New-BcCompilerFolderFromNuGet {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ArtifactUrl,
        [Parameter(Mandatory = $true)]
        [string] $CompilerFolder,
        [Parameter(Mandatory = $false)]
        [string] $VsixFile = '',
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $AppFolders = @()
    )

    $parts = $ArtifactUrl.Split('?')[0].Split('/')
    if ($parts.Count -lt 6) {
        throw "Invalid artifact URL: $ArtifactUrl"
    }
    $bcVersion = $parts[4]
    $country = $parts[5]

    $policy = $VsixFile
    if ($policy -eq '') { $policy = 'default' }
    if (@('default', 'latest', 'preview') -notcontains $policy) {
        throw "vsixFile '$VsixFile' is not supported with symbols from NuGet. Use 'default', 'latest' or 'preview', or set symbolsSource to 'artifact'."
    }

    if (Test-Path $CompilerFolder) {
        Remove-Item $CompilerFolder -Recurse -Force
    }
    $packageFolder = Join-Path $CompilerFolder 'packages'
    $symbolsFolder = Join-Path $CompilerFolder 'symbols'
    $binFolder = Join-Path $CompilerFolder 'compiler/extension/bin'
    New-Item $packageFolder -ItemType Directory -Force | Out-Null
    New-Item $symbolsFolder -ItemType Directory -Force | Out-Null
    New-Item $binFolder -ItemType Directory -Force | Out-Null

    $symbolsFeed = Get-NuGetFlatContainerUrl -FeedIndexUrl $script:MSSymbolsFeedUrl

    # Resolve the application symbols package for this exact Business Central build
    $applicationPackage = Get-BcApplicationSymbolsPackageName -Country $country
    $applicationVersions = Get-NuGetPackageVersions -FlatContainerUrl $symbolsFeed -PackageId $applicationPackage
    $applicationVersion = Select-BcSymbolsVersion -Versions $applicationVersions -ArtifactVersion $bcVersion
    if (-not $applicationVersion) {
        throw "No symbols found on the MSSymbols feed for $applicationPackage matching Business Central $bcVersion. Set symbolsSource to 'artifact' to build from the artifact instead."
    }
    Write-Host "Application symbols: $applicationPackage $applicationVersion"

    # Resolve the AL compiler
    $compilerPackage = Get-ALCompilerPackageName
    $compilerVersions = Get-NuGetPackageVersions -FlatContainerUrl $script:NuGetOrgFlatContainerUrl -PackageId $compilerPackage
    $compilerVersion = Select-ALCompilerVersion -Versions $compilerVersions -BcVersion $bcVersion -Policy $policy
    Write-Host "AL compiler:         $compilerPackage $compilerVersion"

    $compilerFile = Join-Path $packageFolder 'compiler.nupkg'
    $applicationFile = Join-Path $packageFolder 'application.nupkg'
    Get-FilesInParallel -Downloads @(
        @{ Url = "$script:NuGetOrgFlatContainerUrl/$($compilerPackage.ToLowerInvariant())/$compilerVersion/$($compilerPackage.ToLowerInvariant()).$compilerVersion.nupkg"; File = $compilerFile }
        @{ Url = "$symbolsFeed/$($applicationPackage.ToLowerInvariant())/$applicationVersion/$($applicationPackage.ToLowerInvariant()).$applicationVersion.nupkg"; File = $applicationFile }
    )

    # Walk the declared dependency closure of the application package. It is shallow -
    # System Application, Business Foundation, Base Application and Platform - but it is
    # resolved rather than assumed, so a change on Microsoft's side is picked up.
    $resolved = @{}
    $pending = @()
    foreach ($dependency in (Get-NuGetPackageDependencies -PackageFile $applicationFile)) {
        $pending += $dependency
    }
    # Whatever the apps themselves declare a Microsoft dependency on - test toolkit
    # included - is seeded here and resolved through the same closure walk.
    # Declared dependencies are required: if one cannot be resolved the compile would
    # fail later with an AL1022 naming a package cache folder, which tells the user
    # nothing about why. Fail here instead, naming the dependency and the feed.
    $required = @{}
    foreach ($package in (Get-MicrosoftDependencyPackages -AppFolders $AppFolders -Country $country)) {
        Write-Host "Declared Microsoft dependency: $package"
        $required[$package.ToLowerInvariant()] = $true
        $pending += $package
    }

    while ($pending.Count -gt 0) {
        $unresolved = @($pending | Where-Object { -not $resolved.ContainsKey($_.ToLowerInvariant()) })
        if ($unresolved.Count -eq 0) {
            break
        }
        # One parallel round trip for every version list in this level of the closure
        $versionLists = Get-NuGetPackageVersionsInParallel -FlatContainerUrl $symbolsFeed -PackageIds $unresolved

        $batch = @()
        $next = @()
        foreach ($packageId in $unresolved) {
            $id = $packageId.ToLowerInvariant()
            if ($resolved.ContainsKey($id)) {
                continue
            }
            $versions = $versionLists[$id]
            $version = Select-BcSymbolsVersion -Versions $versions -ArtifactVersion $applicationVersion
            if (-not $version) {
                # Platform carries its own version line, so fall back to the highest available
                $version = Select-NuGetVersionInRange -Versions $versions -Range '0.0.0.0'
            }
            if (-not $version) {
                if ($required.ContainsKey($id)) {
                    throw "No symbols package '$packageId' matching Business Central $bcVersion was found on the MSSymbols feed. This dependency is declared in an app.json being compiled. Set symbolsSource to 'artifact' if this app cannot be built from NuGet symbols."
                }
                Write-Host "::Notice::No symbols package found for $packageId; skipping"
                continue
            }
            $file = Join-Path $packageFolder "$id.nupkg"
            $resolved[$id] = $file
            $batch += @{ Url = "$symbolsFeed/$id/$version/$id.$version.nupkg"; File = $file }
        }
        if ($batch.Count -gt 0) {
            Get-FilesInParallel -Downloads $batch
            foreach ($download in $batch) {
                foreach ($dependency in (Get-NuGetPackageDependencies -PackageFile $download.File)) {
                    if (-not $resolved.ContainsKey($dependency.ToLowerInvariant())) {
                        $next += $dependency
                    }
                }
            }
        }
        $pending = $next
    }

    # Stage the symbols
    $appCount = Expand-AppsFromNuGetPackage -PackageFile $applicationFile -DestinationFolder $symbolsFolder
    foreach ($file in $resolved.Values) {
        $appCount += Expand-AppsFromNuGetPackage -PackageFile $file -DestinationFolder $symbolsFolder
    }

    # Stage the compiler. The generic package puts the tools under tools/net8.0/any;
    # the platform-specific ones use lib/net8.0. Support both so the package choice can
    # change without breaking this.
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    $zip = [System.IO.Compression.ZipFile]::OpenRead($compilerFile)
    try {
        $prefix = ''
        foreach ($candidate in @('tools/net8.0/any/', 'lib/net8.0/')) {
            if (@($zip.Entries | Where-Object { $_.FullName.StartsWith($candidate) }).Count -gt 0) {
                $prefix = $candidate
                break
            }
        }
        if (-not $prefix) {
            throw "Could not find the AL tools in $compilerPackage $compilerVersion (expected tools/net8.0/any or lib/net8.0)"
        }
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.StartsWith($prefix) -and $entry.Name) {
                $relative = $entry.FullName.Substring($prefix.Length)
                $target = Join-Path $binFolder $relative
                $targetFolder = [System.IO.Path]::GetDirectoryName($target)
                if (-not (Test-Path $targetFolder)) {
                    New-Item $targetFolder -ItemType Directory -Force | Out-Null
                }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    # altool resolves a named analyzer (--analyzers PTECop) to <bin>/../Analyzers/<dll>,
    # which is where the AL Language vsix keeps them. The NuGet package puts them next to
    # alc instead, so mirror them into the folder altool actually probes. Get-CustomAnalyzers
    # looks in <bin>/Analyzers first and falls back to <bin>, so both stay satisfied.
    $analyzersFolder = Join-Path (Split-Path $binFolder -Parent) 'Analyzers'
    New-Item $analyzersFolder -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path $binFolder -Filter 'Microsoft.Dynamics.Nav.*' | Where-Object {
        $_.Name -like '*Cop.dll' -or $_.Name -like '*Cop.deps.json' -or $_.Name -like 'Microsoft.Dynamics.Nav.Analyzers.Common.*'
    } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $analyzersFolder $_.Name) -Force
    }

    Add-ALToolLaunchers -BinFolder $binFolder

    Remove-Item $packageFolder -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Compiler folder ready: $appCount symbol apps staged in $symbolsFolder"
    return $CompilerFolder
}

Export-ModuleMember -Function Test-OnWindows, Get-ALCompilerPackageName, Add-ALToolLaunchers, `
    Select-BcSymbolsVersion, Get-NuGetFlatContainerUrl, Get-NuGetPackageVersions, `
    Get-NuGetPackageVersionsInParallel, Get-FilesInParallel, Get-NuGetPackageDependencies, `
    Expand-AppsFromNuGetPackage, Select-NuGetVersionInRange, Select-ALCompilerVersion, `
    Get-BcApplicationSymbolsPackageName, Get-BcSymbolsPackageNameForDependency, `
    Get-MicrosoftDependencyPackages, Test-SymbolsFromNuGetSupported, `
    New-BcCompilerFolderFromNuGet
