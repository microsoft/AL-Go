$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageAggregateFormat.psm1" -Resolve) `
    -DisableNameChecking

$script:CoverageObjectTypeNames = @{
    0 = "TableData"
    1 = "Table"
    3 = "Report"
    5 = "Codeunit"
    6 = "XmlPort"
    8 = "Page"
    9 = "Query"
}
$script:MaximumValueLength = 160
$script:MaximumSummaryBytes = 900KB

function Get-CoverageArray {
    Param($Value)

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Expected an array."
    }
    return @($Value)
}

function Resolve-CoverageSourceRootDetail {
    Param(
        [string] $SourceIdentity,
        [object[]] $SourceRootDetails
    )

    $source = "$SourceIdentity".Replace('\', '/').Trim('/').ToLowerInvariant()
    $matchingDetails = @()
    foreach ($detail in $SourceRootDetails) {
        $root = "$($detail.Identity)"
        if ($root -eq "." -or $source -eq $root -or $source.StartsWith(
                "$root/", [System.StringComparison]::OrdinalIgnoreCase)) {
            $matchingDetails += $detail
        }
    }
    if ($matchingDetails.Count -eq 0) {
        return $null
    }
    $ordered = @($matchingDetails |
        Sort-Object @{ Expression = { "$($_.Identity)".Length }; Descending = $true })
    if ($ordered.Count -gt 1 -and
        "$($ordered[0].Identity)".Length -eq "$($ordered[1].Identity)".Length) {
        return $null
    }
    return $ordered[0]
}

function ConvertTo-SafeCoverageText {
    <#
    .SYNOPSIS
        Escapes an untrusted value for Markdown and embedded HTML.
    #>
    Param(
        $Value,
        [int] $MaximumLength = $script:MaximumValueLength
    )

    $text = if ($null -eq $Value) { "" } else { "$Value" }
    $text = $text.Replace("`r`n", " ").Replace("`n", " ").Replace("`r", " ")
    if ($text.Length -gt $MaximumLength) {
        $suffix = "..."
        $text = $text.Substring(0, [Math]::Max(0, $MaximumLength - $suffix.Length)) + $suffix
    }
    $text = $text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
    $text = $text.Replace('\', '\\')
    foreach ($character in @('*', '_', '[', ']', '(', ')', '`', '!', '~', '|')) {
        $text = $text.Replace($character, "\$character")
    }
    return $text
}

function Limit-CoverageSummary {
    <#
    .SYNOPSIS
        Bounds a summary by UTF-8 byte length.
    #>
    Param(
        [AllowEmptyString()]
        [string] $Summary,
        [int] $MaximumBytes = $script:MaximumSummaryBytes
    )

    $encoding = [System.Text.Encoding]::UTF8
    if ($encoding.GetByteCount($Summary) -le $MaximumBytes) {
        return $Summary
    }

    $suffix = "`n`n_Summary truncated to stay within the GitHub job summary limit._"
    $available = [Math]::Max(0, $MaximumBytes - $encoding.GetByteCount($suffix))
    $low = 0
    $high = $Summary.Length
    while ($low -lt $high) {
        $middle = [int][Math]::Ceiling(($low + $high) / 2.0)
        if ($encoding.GetByteCount($Summary.Substring(0, $middle)) -le $available) {
            $low = $middle
        }
        else {
            $high = $middle - 1
        }
    }
    return $Summary.Substring(0, $low) + $suffix
}

function Test-CodeCoverageSummaryRequested {
    <#
    .SYNOPSIS
        Tests whether project settings request the supplied summary scope.
    #>
    Param(
        [hashtable] $Settings,
        [ValidateSet("project", "repository")]
        [string] $Scope
    )

    if (-not $Settings.ContainsKey("useSeparateTestAction")) {
        return $false
    }
    $separateSettings = $Settings.useSeparateTestAction
    if ($separateSettings -isnot [System.Collections.IDictionary] -or
        -not $separateSettings.Contains("codeCoverageSummary")) {
        return $false
    }
    $requested = "$($separateSettings.codeCoverageSummary)".ToLowerInvariant()
    return $requested -eq "both" -or $requested -eq $Scope
}

function Read-CoverageJson {
    Param(
        [string] $Path,
        [string] $Kind
    )

    try {
        $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json |
            ConvertTo-HashTable -recurse
        if ($data -isnot [System.Collections.IDictionary]) {
            throw "The JSON root must be an object."
        }
        return @{
            Valid = $true
            Data = $data
            Reason = ""
        }
    }
    catch {
        return @{
            Valid = $false
            Data = $null
            Reason = "$Kind JSON is corrupt or invalid."
        }
    }
}

function ConvertTo-CoverageDimensionIdentity {
    Param([AllowEmptyString()][string] $Value)
    return $Value.Replace('\', '/').Trim('/').ToLowerInvariant()
}

function Get-CoverageStatusFiles {
    Param([string] $CoveragePath)

    if (-not (Test-Path -LiteralPath $CoveragePath)) {
        return @()
    }
    if (Test-Path -LiteralPath $CoveragePath -PathType Leaf) {
        if ([System.IO.Path]::GetFileName($CoveragePath) -eq "coverage-status.json") {
            return @((Get-Item -LiteralPath $CoveragePath).FullName)
        }
        return @()
    }
    return @(Get-ChildItem -LiteralPath $CoveragePath -Filter "coverage-status.json" -File -Recurse |
        ForEach-Object { $_.FullName } |
        Sort-Object)
}

function Get-CoverageSourceRootDetails {
    Param(
        [hashtable] $Status,
        [string[]] $SourceRoots
    )

    if (-not $Status.Contains("sourceRootDetails")) {
        return @()
    }
    try {
        $details = @(Get-CoverageArray $Status.sourceRootDetails)
        if ($details.Count -ne $SourceRoots.Count) {
            return @()
        }
        if ($details.Count -eq 0) {
            return @()
        }
        $result = @()
        foreach ($index in 0..($details.Count - 1)) {
            $detail = $details[$index]
            if ($detail -isnot [System.Collections.IDictionary]) {
                return @()
            }
            foreach ($property in @("path", "kind", "appId", "appName")) {
                if (-not $detail.Contains($property)) {
                    return @()
                }
            }
            $path = "$($detail.path)".Trim().Replace('\', '/').Trim('/')
            $expectedPath = "$($SourceRoots[$index])".Trim().Replace('\', '/').Trim('/')
            $kind = "$($detail.kind)".ToLowerInvariant()
            if ($path -cne $expectedPath -or $kind -notin @("app", "test", "unknown")) {
                return @()
            }
            $result += @{
                Path = $path
                Identity = $path.ToLowerInvariant()
                Kind = $kind
                AppId = "$($detail.appId)"
                AppName = "$($detail.appName)"
            }
        }
        return @($result)
    }
    catch {
        return @()
    }
}

function New-CoverageApplicationModels {
    Param([object[]] $SourceRootDetails)

    $apps = @()
    foreach ($detail in $SourceRootDetails) {
        if ("$($detail.Kind)" -ne "app") {
            continue
        }
        $appName = "$($detail.AppName)"
        if ([string]::IsNullOrWhiteSpace($appName)) {
            $appName = @("$($detail.Path)" -split '/')[-1]
        }
        $apps += @{
            Root = "$($detail.Path)"
            RootIdentity = "$($detail.Identity)"
            AppId = "$($detail.AppId)"
            AppName = $appName
            LineComplete = $true
            Lines = @{}
        }
    }
    return @($apps)
}

function Merge-CoverageRunIntoApplications {
    Param(
        [object[]] $Applications,
        [hashtable] $Scope,
        [object[]] $SourceRootDetails,
        [bool] $BlocksAllApplications,
        [bool] $LineGlobalUnsafe,
        [string[]] $LineAffectedSources
    )

    if ($Applications.Count -eq 0) {
        return
    }
    $appsByRoot = @{}
    foreach ($app in $Applications) {
        $appsByRoot["$($app.RootIdentity)"] = $app
        if ($BlocksAllApplications -or $LineGlobalUnsafe) {
            $app.LineComplete = $false
        }
    }

    foreach ($rootIdentity in @($Scope.ApplicationLines.Keys)) {
        if (-not $appsByRoot.ContainsKey("$rootIdentity")) {
            continue
        }
        $app = $appsByRoot["$rootIdentity"]
        foreach ($key in @($Scope.ApplicationLines[$rootIdentity].Keys)) {
            Merge-CoverageLine -Lines $app.Lines -Key "$key" `
                -Covered ([bool]$Scope.ApplicationLines[$rootIdentity][$key])
        }
        $Scope.ApplicationLines[$rootIdentity].Clear()
    }

    if ($BlocksAllApplications -or $LineGlobalUnsafe) {
        return
    }
    foreach ($sourceIdentity in $LineAffectedSources) {
        $detail = Resolve-CoverageSourceRootDetail -SourceIdentity $sourceIdentity `
            -SourceRootDetails $SourceRootDetails
        if (-not $detail -or "$($detail.Kind)" -eq "unknown") {
            foreach ($app in $Applications) {
                $app.LineComplete = $false
            }
        }
        elseif ("$($detail.Kind)" -eq "app" -and
            $appsByRoot.ContainsKey("$($detail.Identity)")) {
            $appsByRoot["$($detail.Identity)"].LineComplete = $false
        }
    }
}

function Merge-CoverageLine {
    Param(
        [System.Collections.IDictionary] $Lines,
        [string] $Key,
        [bool] $Covered
    )

    if ($Lines.Contains($Key)) {
        $Lines[$Key] = [bool]$Lines[$Key] -or $Covered
    }
    else {
        $Lines[$Key] = $Covered
    }
}

function New-EmptyProjectCoverageModel {
    Param(
        [string] $Project,
        [string] $ProjectName,
        [string] $BuildMode
    )

    return @{
        Reasons = @()
        LineComplete = $false
        LineReasons = @()
        Notices = @()
        Project = $Project
        ProjectName = $ProjectName
        BuildMode = $BuildMode
        SourceRoots = @()
        SourceRootDetails = @()
        ApplicationMetadataAvailable = $false
        Runs = @()
        Apps = @()
        Lines = @{}
        ExcludedLineFacts = 0
        StatusPath = ""
    }
}

function Get-ProjectCoverageModelFromStatus {
    Param(
        [string] $StatusPath,
        [hashtable] $ExpectedDimension = $null
    )

    $fallbackProject = if ($ExpectedDimension) { "$($ExpectedDimension.project)" } else { "." }
    $fallbackName = if ($ExpectedDimension) { "$($ExpectedDimension.projectName)" } else { "" }
    $fallbackBuildMode = if ($ExpectedDimension) { "$($ExpectedDimension.buildMode)" } else { "" }
    $model = New-EmptyProjectCoverageModel -Project $fallbackProject -ProjectName $fallbackName -BuildMode $fallbackBuildMode
    $model.StatusPath = $StatusPath
    $statusJson = Read-CoverageJson -Path $StatusPath -Kind "Coverage status"
    if (-not $statusJson.Valid) {
        $model.Reasons = @($statusJson.Reason)
        return $model
    }

    $status = $statusJson.Data
    foreach ($property in @("project", "projectName", "buildMode", "sourceRoots", "runs")) {
        if (-not $status.Contains($property)) {
            $model.Reasons = @("Coverage status is missing required data.")
            return $model
        }
    }
    try {
        $sourceRoots = @(Get-CoverageArray $status.sourceRoots | ForEach-Object { "$_" })
        $statusRuns = @(Get-CoverageArray $status.runs)
    }
    catch {
        $model.Reasons = @("Coverage status is missing required data.")
        return $model
    }

    $model.Project = "$($status.project)"
    $model.ProjectName = "$($status.projectName)"
    $model.BuildMode = "$($status.buildMode)"
    $model.SourceRoots = $sourceRoots
    $model.SourceRootDetails = @(Get-CoverageSourceRootDetails -Status $status -SourceRoots $sourceRoots)
    if ($status.Contains("sourceRootDetails")) {
        try {
            $declaredSourceRootDetails = @(Get-CoverageArray $status.sourceRootDetails)
            $model.ApplicationMetadataAvailable =
                $declaredSourceRootDetails.Count -eq $sourceRoots.Count -and
                $declaredSourceRootDetails.Count -eq $model.SourceRootDetails.Count
        }
        catch {
            $model.ApplicationMetadataAvailable = $false
        }
    }
    $model.Apps = @(New-CoverageApplicationModels -SourceRootDetails $model.SourceRootDetails)
    $reasons = @()

    if ($ExpectedDimension) {
        if ((ConvertTo-CoverageDimensionIdentity "$($ExpectedDimension.project)") -ne
                (ConvertTo-CoverageDimensionIdentity $model.Project) -or
            "$($ExpectedDimension.buildMode)" -ine $model.BuildMode) {
            $reasons += "Coverage status does not match the expected project and build mode."
        }
    }

    $aggregateResult = $null
    if (-not $status.Contains("aggregate")) {
        $reasons += "The published code coverage aggregate is missing."
    }
    else {
        try {
            if ($status.aggregate -isnot [string] -or
                "$($status.aggregate)" -cne "coverage-aggregate.bin.gz") {
                throw "Coverage aggregate reference is invalid."
            }
            $statusDirectory = Split-Path -Path $StatusPath -Parent
            $aggregateResult = Read-CodeCoverageAggregate -path ([System.IO.Path]::GetFullPath(
                (Join-Path $statusDirectory "$($status.aggregate)"))
            )
            if (-not $aggregateResult.Valid) {
                throw $aggregateResult.Reason
            }
            $appsByRoot = @{}
            foreach ($app in $model.Apps) {
                $appsByRoot["$($app.RootIdentity)"] = $app
            }
            foreach ($rootIdentity in @($aggregateResult.ApplicationLines.Keys)) {
                if (-not $appsByRoot.ContainsKey("$rootIdentity")) {
                    throw "Coverage aggregate references an unknown application root."
                }
                foreach ($key in @($aggregateResult.ApplicationLines[$rootIdentity].Keys)) {
                    Merge-CoverageLine -Lines $appsByRoot["$rootIdentity"].Lines -Key "$key" `
                        -Covered ([bool]$aggregateResult.ApplicationLines[$rootIdentity][$key])
                }
            }
        }
        catch {
            $aggregateResult = $null
            $aggregateReason = "The published code coverage aggregate is invalid. $($_.Exception.Message)"
            $reasons += $aggregateReason
        }
    }
    $projectReasons = @($reasons)
    $runModels = @()
    foreach ($run in $statusRuns) {
        if ($run -isnot [System.Collections.IDictionary]) {
            $reasons += "Coverage status contains an invalid run."
            continue
        }
        $appId = if ($run.Contains("appId")) { "$($run.appId)" } else { "" }
        $appName = if ($run.Contains("appName")) { "$($run.appName)" } else { "" }
        $state = if ($run.Contains("state")) { "$($run.state)".ToLowerInvariant() } else { "unknown" }
        $runReasons = @()
        if ($state -notin @("pending", "running", "complete", "incomplete", "failed", "unsupported")) {
            $runReasons += "Run state is invalid."
        }
        elseif ($state -notin @("complete", "incomplete")) {
            $runReasons += "Run state is $state."
        }
        $runNotices = @()
        if ($state -eq "incomplete") {
            $runNotices += "Run output is globally incomplete and was evaluated by repository scope."
        }

        $scope = @{
            IncludedLineObjects = @{}
            IncludedLineSources = @{}
            ExcludedLineObjects = @{}
            ApplicationLines = @{}
            LineReasons = @()
            ExcludedLineFacts = 0
        }
        $runLineReasons = @()
        $lineGlobalUnsafe = $false
        $lineAffectedSources = @()
        if ($runReasons.Count -eq 0) {
            foreach ($property in @(
                    "lineReasons", "notices", "lineGlobalUnsafe",
                    "lineAffectedSources", "excludedLineFacts"
                )) {
                if (-not $run.Contains($property)) {
                    $runReasons += "Coverage status is missing the run assessment."
                    break
                }
            }
            if ($runReasons.Count -eq 0 -and $run.lineGlobalUnsafe -isnot [bool]) {
                $runReasons += "Coverage status contains an invalid run assessment."
            }
            $excludedLineFacts = 0
            if ($runReasons.Count -eq 0 -and
                (-not [int]::TryParse("$($run.excludedLineFacts)", [ref]$excludedLineFacts) -or
                    $excludedLineFacts -lt 0)) {
                $runReasons += "Coverage status contains an invalid run assessment."
            }
            if ($runReasons.Count -eq 0) {
                try {
                    $model.ExcludedLineFacts += $excludedLineFacts
                    $runLineReasons += @(Get-CoverageArray $run.lineReasons |
                        ForEach-Object { "$_" })
                    $runNotices += @(Get-CoverageArray $run.notices |
                        ForEach-Object { "$_" })
                    $lineGlobalUnsafe = [bool]$run.lineGlobalUnsafe
                    $lineAffectedSources = @(Get-CoverageArray $run.lineAffectedSources |
                        ForEach-Object { "$_" })
                }
                catch {
                    $runReasons += "Coverage status contains an invalid run assessment."
                }
            }
        }

        $runLineComplete = $projectReasons.Count -eq 0 -and $runReasons.Count -eq 0 -and
            $runLineReasons.Count -eq 0 -and -not $lineGlobalUnsafe
        if ($runLineComplete) {
            foreach ($sourceIdentity in $lineAffectedSources) {
                $detail = Resolve-CoverageSourceRootDetail -SourceIdentity $sourceIdentity `
                    -SourceRootDetails $model.SourceRootDetails
                if (-not $detail -or "$($detail.Kind)" -in @("app", "unknown")) {
                    $runLineComplete = $false
                    break
                }
            }
        }
        Merge-CoverageRunIntoApplications -Applications $model.Apps -Scope $scope `
            -SourceRootDetails $model.SourceRootDetails `
            -BlocksAllApplications ($projectReasons.Count -gt 0 -or $runReasons.Count -gt 0) `
            -LineGlobalUnsafe $lineGlobalUnsafe -LineAffectedSources $lineAffectedSources
        $runModels += @{
            AppId = $appId
            AppName = $appName
            State = $state
            LineComplete = $runLineComplete
            Reasons = @($runReasons)
            LineReasons = @($runLineReasons | Select-Object -Unique)
            Notices = @($runNotices | Select-Object -Unique)
        }
        foreach ($runReason in $runReasons) {
            $reasons += "$appName`: $runReason"
        }
        foreach ($runReason in $runLineReasons) {
            $model.LineReasons += "$appName`: $runReason"
        }
        foreach ($notice in $runNotices) {
            $model.Notices += "$appName`: $notice"
        }
    }
    if ($statusRuns.Count -eq 0) {
        $reasons += "Coverage status contains no test-app runs."
        foreach ($app in $model.Apps) {
            $app.LineComplete = $false
        }
    }

    $model.Runs = @($runModels)
    $model.Apps = @($model.Apps |
        Sort-Object @{ Expression = { "$($_.AppName)".ToLowerInvariant() }; Descending = $false },
                    @{ Expression = "AppId"; Descending = $false },
                    @{ Expression = "RootIdentity"; Descending = $false })
    $model.Reasons = @($reasons | Select-Object -Unique)
    $model.LineReasons = @($model.LineReasons | Select-Object -Unique)
    $model.Notices = @($model.Notices | Select-Object -Unique)
    if (-not $model.ApplicationMetadataAvailable) {
        $model.LineReasons += "Coverage status does not identify regular application roots."
    }
    elseif ($model.Apps.Count -eq 0) {
        $model.LineReasons += "Coverage status contains no regular application roots."
    }
    $model.LineComplete = $model.Reasons.Count -eq 0 -and $model.LineReasons.Count -eq 0 -and
        @($model.Apps | Where-Object { -not [bool]$_.LineComplete }).Count -eq 0
    if ($model.LineComplete) {
        foreach ($app in $model.Apps) {
            foreach ($key in $app.Lines.Keys) {
                Merge-CoverageLine -Lines $model.Lines -Key "$key" `
                    -Covered ([bool]$app.Lines[$key])
            }
        }
    }
    return $model
}

function Get-ProjectCoverageModel {
    <#
    .SYNOPSIS
        Builds the project aggregate without throwing for incomplete coverage data.
    #>
    Param(
        [string] $CoveragePath,
        [string] $Project = "."
    )

    $statusFiles = @(Get-CoverageStatusFiles -CoveragePath $CoveragePath)
    if ($statusFiles.Count -ne 1) {
        $model = New-EmptyProjectCoverageModel -Project $Project -ProjectName "" -BuildMode ""
        $model.Reasons = if ($statusFiles.Count -eq 0) {
            @("The coverage status artifact is missing.")
        }
        else {
            @("Multiple coverage status artifacts were found for the project.")
        }
        return $model
    }
    return Get-ProjectCoverageModelFromStatus -StatusPath $statusFiles[0]
}

function Get-ExpectedCoverageDimensions {
    Param([string] $BuildOrderJson)

    try {
        $buildOrderWrapper = "{`"entries`":$BuildOrderJson}" |
            ConvertFrom-Json |
            ConvertTo-HashTable -recurse
        $entries = @(Get-CoverageArray $buildOrderWrapper.entries)
        if ($entries.Count -eq 0) {
            throw "Missing build dimensions."
        }
        $dimensions = @()
        foreach ($entry in $entries) {
            if ($entry -isnot [System.Collections.IDictionary] -or
                -not $entry.Contains("buildDimensions")) {
                throw "Missing build dimensions."
            }
            $dimensions += @(Get-CoverageArray $entry.buildDimensions)
        }
        return @{
            Valid = $true
            Dimensions = @($dimensions | Where-Object {
                    $_ -is [System.Collections.IDictionary] -and
                    $_.Contains("codeCoverageRepositorySummary") -and
                    [bool]$_.codeCoverageRepositorySummary
                })
            Reason = ""
        }
    }
    catch {
        return @{
            Valid = $false
            Dimensions = @()
            Reason = "Build order JSON does not contain valid expected coverage dimensions."
        }
    }
}

function Get-RepositoryApplications {
    Param([object[]] $ProjectModels)

    $applications = @{}
    $blockedProjects = @{}
    foreach ($projectModel in $ProjectModels) {
        $projectIdentity = ConvertTo-CoverageDimensionIdentity "$($projectModel.Project)"
        if (($projectModel.Runs.Count -eq 0 -and $projectModel.Reasons.Count -gt 0) -or
            -not [bool]$projectModel.ApplicationMetadataAvailable) {
            $blockedProjects[$projectIdentity] = $true
        }
        $projectDisplay = if ([string]::IsNullOrWhiteSpace("$($projectModel.ProjectName)")) {
            "$($projectModel.Project)"
        }
        else {
            "$($projectModel.ProjectName)"
        }
        foreach ($projectApp in @($projectModel.Apps)) {
            $appId = "$($projectApp.AppId)"
            $rootIdentity = "$($projectApp.RootIdentity)"
            $key = "$projectIdentity|$($appId.ToLowerInvariant())|$rootIdentity"
            if (-not $applications.ContainsKey($key)) {
                $applications[$key] = @{
                    Project = $projectDisplay
                    ProjectIdentity = $projectIdentity
                    AppId = $appId
                    AppName = "$($projectApp.AppName)"
                    RootIdentity = $rootIdentity
                    LineComplete = $true
                    Lines = @{}
                }
            }
            $application = $applications[$key]
            if (-not [bool]$projectApp.LineComplete) {
                $application.LineComplete = $false
                continue
            }
            foreach ($factKey in @($projectApp.Lines.Keys)) {
                Merge-CoverageLine -Lines $application.Lines -Key "$factKey" `
                    -Covered ([bool]$projectApp.Lines[$factKey])
            }
        }
    }

    foreach ($application in $applications.Values) {
        if ($blockedProjects.ContainsKey($application.ProjectIdentity)) {
            $application.LineComplete = $false
        }
    }
    return @($applications.Values |
        Sort-Object @{ Expression = { "$($_.Project)".ToLowerInvariant() }; Descending = $false },
                    @{ Expression = { "$($_.AppName)".ToLowerInvariant() }; Descending = $false },
                    @{ Expression = "AppId"; Descending = $false },
                    @{ Expression = "RootIdentity"; Descending = $false })
}

function Get-RepositoryCoverageModel {
    <#
    .SYNOPSIS
        Builds a repository aggregate from expected build dimensions and downloaded artifacts.
    #>
    Param(
        [string] $CoveragePath,
        [string] $BuildOrderJson
    )

    $repositoryModel = @{
        Reasons = @()
        LineComplete = $false
        LineReasons = @()
        Notices = @()
        Projects = @()
        Apps = @()
        Lines = @{}
        ExcludedLineFacts = 0
    }
    $expectedResult = Get-ExpectedCoverageDimensions -BuildOrderJson $BuildOrderJson
    if (-not $expectedResult.Valid) {
        $repositoryModel.Reasons = @($expectedResult.Reason)
        return $repositoryModel
    }
    $dimensions = @($expectedResult.Dimensions)
    if ($dimensions.Count -eq 0) {
        $repositoryModel.Reasons = @("No repository coverage dimensions were expected.")
        return $repositoryModel
    }

    $statusEntries = @()
    foreach ($statusPath in @(Get-CoverageStatusFiles -CoveragePath $CoveragePath)) {
        $statusJson = Read-CoverageJson -Path $statusPath -Kind "Coverage status"
        if ($statusJson.Valid -and $statusJson.Data.Contains("project") -and
            $statusJson.Data.Contains("buildMode")) {
            $statusEntries += @{
                Path = $statusPath
                Project = "$($statusJson.Data.project)"
                BuildMode = "$($statusJson.Data.buildMode)"
            }
        }
    }

    $projectModels = @()
    $reasons = @()
    foreach ($dimension in $dimensions) {
        $requiredProperties = @("project", "projectName", "buildMode",
            "codeCoverageRepositorySummary")
        $missingProperty = $false
        foreach ($property in $requiredProperties) {
            if ($dimension -isnot [System.Collections.IDictionary] -or -not $dimension.Contains($property)) {
                $missingProperty = $true
            }
        }
        if ($missingProperty) {
            $invalidModel = New-EmptyProjectCoverageModel -Project "Unknown" -ProjectName "" -BuildMode ""
            $invalidModel.Reasons = @("Expected build dimension is missing required data.")
            $projectModels += $invalidModel
            $reasons += "An expected build dimension is invalid."
            $repositoryModel.LineReasons += "An expected build dimension is invalid."
            continue
        }

        $statusMatches = @($statusEntries | Where-Object {
                (ConvertTo-CoverageDimensionIdentity $_.Project) -eq
                    (ConvertTo-CoverageDimensionIdentity "$($dimension.project)") -and
                $_.BuildMode -ieq "$($dimension.buildMode)"
            })
        if ($statusMatches.Count -ne 1) {
            $missingModel = New-EmptyProjectCoverageModel -Project "$($dimension.project)" `
                -ProjectName "$($dimension.projectName)" -BuildMode "$($dimension.buildMode)"
            $missingReason = if ($statusMatches.Count -eq 0) {
                "Expected coverage artifact is missing."
            }
            else {
                "Multiple matching coverage artifacts were found."
            }
            $missingModel.Reasons = @($missingReason)
            $projectModels += $missingModel
            $reasons += "$($dimension.project) [$($dimension.buildMode)]: $missingReason"
            $repositoryModel.LineReasons += "$($dimension.project) [$($dimension.buildMode)]: $missingReason"
            continue
        }

        $projectModel = Get-ProjectCoverageModelFromStatus -StatusPath $statusMatches[0].Path `
            -ExpectedDimension $dimension
        $projectModels += $projectModel
        foreach ($reason in $projectModel.Reasons) {
            $reasons += "$($projectModel.Project) [$($projectModel.BuildMode)]: $reason"
            $repositoryModel.LineReasons += "$($projectModel.Project) [$($projectModel.BuildMode)]: $reason"
        }
        foreach ($reason in $projectModel.LineReasons) {
            $repositoryModel.LineReasons += "$($projectModel.Project) [$($projectModel.BuildMode)]: $reason"
        }
        if (-not $projectModel.LineComplete -and
            $projectModel.Reasons.Count -eq 0 -and $projectModel.LineReasons.Count -eq 0) {
            $repositoryModel.LineReasons += "$($projectModel.Project) [$($projectModel.BuildMode)]: Regular application line coverage is incomplete."
        }
        $repositoryModel.Notices += $projectModel.Notices
    }

    $repositoryModel.Projects = @($projectModels)
    $repositoryModel.Apps = @(Get-RepositoryApplications -ProjectModels $projectModels)
    $repositoryModel.Reasons = @($reasons | Select-Object -Unique)
    $repositoryModel.LineReasons = @($repositoryModel.LineReasons | Select-Object -Unique)
    $repositoryModel.Notices = @($repositoryModel.Notices | Select-Object -Unique)
    foreach ($projectModel in $projectModels) {
        $repositoryModel.ExcludedLineFacts += $projectModel.ExcludedLineFacts
        if ($projectModel.LineComplete) {
            foreach ($key in @($projectModel.Lines.Keys)) {
                Merge-CoverageLine -Lines $repositoryModel.Lines -Key "$key" `
                    -Covered ([bool]$projectModel.Lines[$key])
            }
        }
    }
    $repositoryModel.LineComplete = $repositoryModel.LineReasons.Count -eq 0
    return $repositoryModel
}

function Get-CoverageMetrics {
    <#
    .SYNOPSIS
        Calculates covered, uncovered, total, and percentage values for semantic facts.
    #>
    Param([hashtable] $Facts)

    $total = $Facts.Count
    $covered = 0
    foreach ($value in $Facts.Values) {
        if ([bool]$value) {
            $covered++
        }
    }
    $percentage = if ($total -eq 0) { 100.0 } else { [Math]::Round(($covered * 100.0) / $total, 1) }
    return @{
        Total = $total
        Covered = $covered
        Uncovered = $total - $covered
        Percentage = $percentage
    }
}

function Resolve-CoverageObjectAttribution {
    <#
    .SYNOPSIS
        Resolves display attribution for one covered object.
    #>
    Param(
        [int] $ObjectType,
        [int] $ObjectId,
        [AllowEmptyString()][string] $SourcePath
    )

    $name = if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        "-"
    }
    else {
        $leafName = @($SourcePath.Replace('\', '/') -split '/')[-1]
        $extensionIndex = $leafName.LastIndexOf('.')
        if ($extensionIndex -gt 0) {
            $leafName.Substring(0, $extensionIndex)
        }
        else {
            $leafName
        }
    }
    $objectTypeName = if ($script:CoverageObjectTypeNames.ContainsKey($ObjectType)) {
        $script:CoverageObjectTypeNames[$ObjectType]
    }
    else {
        "Object $ObjectType"
    }
    return @{
        Object = "$objectTypeName $ObjectId"
        Name = $name
        Source = $SourcePath
    }
}

function Get-UncoveredObjectRows {
    Param([hashtable] $Lines)

    $objects = @{}
    foreach ($lineKey in $Lines.Keys) {
        if ([bool]$Lines[$lineKey]) {
            continue
        }
        $lineSeparator = $lineKey.LastIndexOf('|')
        $objectIdSeparator = $lineKey.LastIndexOf('|', $lineSeparator - 1)
        $objectTypeSeparator = $lineKey.LastIndexOf('|', $objectIdSeparator - 1)
        if ($lineSeparator -lt 0 -or $objectIdSeparator -lt 0 -or
            $objectTypeSeparator -lt 0) {
            continue
        }
        $sourcePath = $lineKey.Substring(0, $objectTypeSeparator)
        $objectType = [int]$lineKey.Substring(
            $objectTypeSeparator + 1, $objectIdSeparator - $objectTypeSeparator - 1)
        $objectId = [int]$lineKey.Substring(
            $objectIdSeparator + 1, $lineSeparator - $objectIdSeparator - 1)
        $objectKey = "$sourcePath|$objectType|$objectId"
        if (-not $objects.ContainsKey($objectKey)) {
            $objects[$objectKey] = @{
                ObjectType = $objectType
                ObjectId = $objectId
                SourcePath = $sourcePath
                UncoveredLines = 0
            }
        }
        $objects[$objectKey].UncoveredLines++
    }
    return @($objects.Values |
        Sort-Object @{ Expression = "UncoveredLines"; Descending = $true },
                    @{ Expression = "ObjectType"; Descending = $false },
                    @{ Expression = "ObjectId"; Descending = $false } |
        Select-Object -First 10)
}

function Add-CoverageMetricMarkdown {
    Param(
        [System.Text.StringBuilder] $Builder,
        [string] $Label,
        [hashtable] $Metrics,
        [string] $DenominatorName,
        [string] $UncoveredName
    )

    if ($Metrics.Total -eq 0) {
        [void]$Builder.AppendLine("**$Label coverage:** not available (0 $DenominatorName)")
    }
    else {
        [void]$Builder.AppendLine("**$Label coverage:** $($Metrics.Percentage.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture))% ($($Metrics.Covered)/$($Metrics.Total) $DenominatorName, $($Metrics.Uncovered) $UncoveredName)")
    }
    [void]$Builder.AppendLine()
}

function Add-CoverageOverviewMarkdown {
    Param(
        [System.Text.StringBuilder] $Builder,
        [hashtable] $Model
    )

    if (-not $Model.LineComplete) {
        [void]$Builder.AppendLine("> [!WARNING]")
        [void]$Builder.AppendLine("> Coverage data is incomplete. Available metrics are shown only when they can be calculated safely. See the action logs and retained coverage artifacts for details.")
        [void]$Builder.AppendLine()
    }
    if ($Model.LineComplete) {
        Add-CoverageMetricMarkdown -Builder $Builder -Label "Line" `
            -Metrics (Get-CoverageMetrics $Model.Lines) `
            -DenominatorName "executable lines" -UncoveredName "uncovered"
    }
    else {
        [void]$Builder.AppendLine("**Line coverage:** unavailable (coverage data is incomplete or could not be evaluated safely; see the action logs and retained coverage artifacts for details)")
        [void]$Builder.AppendLine()
    }
}

function Add-ApplicationCoverageTable {
    Param(
        [System.Text.StringBuilder] $Builder,
        [object[]] $Applications,
        [switch] $IncludeProject
    )

    if ($IncludeProject) {
        [void]$Builder.AppendLine("| Project | App | Covered lines | Line coverage |")
        [void]$Builder.AppendLine("| :-- | :-- | --: | --: |")
        $sortedApps = @($Applications |
            Sort-Object @{ Expression = { "$($_.Project)".ToLowerInvariant() }; Descending = $false },
                        @{ Expression = { "$($_.AppName)".ToLowerInvariant() }; Descending = $false },
                        @{ Expression = "AppId"; Descending = $false },
                        @{ Expression = "RootIdentity"; Descending = $false })
    }
    else {
        [void]$Builder.AppendLine("| App | Covered lines | Line coverage |")
        [void]$Builder.AppendLine("| :-- | --: | --: |")
        $sortedApps = @($Applications |
            Sort-Object @{ Expression = { "$($_.AppName)".ToLowerInvariant() }; Descending = $false },
                        @{ Expression = "AppId"; Descending = $false },
                        @{ Expression = "RootIdentity"; Descending = $false })
    }

    foreach ($application in $sortedApps) {
        $coveredLines = "unavailable"
        $lineCoverage = "unavailable"
        if ([bool]$application.LineComplete) {
            $metrics = Get-CoverageMetrics $application.Lines
            if ($metrics.Total -gt 0) {
                $coveredLines = "$($metrics.Covered)/$($metrics.Total)"
                $percentage = [Math]::Round(($metrics.Covered * 100.0) / $metrics.Total, 2)
                $lineCoverage = "$($percentage.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture))%"
            }
        }
        if ($IncludeProject) {
            [void]$Builder.AppendLine("| $(ConvertTo-SafeCoverageText $application.Project) | $(ConvertTo-SafeCoverageText $application.AppName) | $coveredLines | $lineCoverage |")
        }
        else {
            [void]$Builder.AppendLine("| $(ConvertTo-SafeCoverageText $application.AppName) | $coveredLines | $lineCoverage |")
        }
    }
    if ($sortedApps.Count -eq 0) {
        $columns = if ($IncludeProject) { 4 } else { 3 }
        [void]$Builder.AppendLine("| $(ConvertTo-SafeCoverageText "No regular apps were available.") $("| " * ($columns - 1))")
    }
}

function Add-UncoveredObjectsMarkdown {
    Param(
        [System.Text.StringBuilder] $Builder,
        [hashtable] $Lines
    )

    [void]$Builder.AppendLine("<details>")
    [void]$Builder.AppendLine("<summary>Top 10 uncovered objects</summary>")
    [void]$Builder.AppendLine()
    $rows = @(Get-UncoveredObjectRows -Lines $Lines)
    if ($rows.Count -eq 0) {
        [void]$Builder.AppendLine("No uncovered objects.")
    }
    else {
        [void]$Builder.AppendLine("| Object | Name | Uncovered executable lines |")
        [void]$Builder.AppendLine("| :-- | :-- | --: |")
        foreach ($row in $rows) {
            $attribution = Resolve-CoverageObjectAttribution -ObjectType $row.ObjectType `
                -ObjectId $row.ObjectId -SourcePath "$($row.SourcePath)"
            [void]$Builder.AppendLine("| $(ConvertTo-SafeCoverageText $attribution.Object) | $(ConvertTo-SafeCoverageText $attribution.Name) | $($row.UncoveredLines) |")
        }
    }
    [void]$Builder.AppendLine()
    [void]$Builder.AppendLine("</details>")
}

function New-ProjectCoverageSummary {
    <#
    .SYNOPSIS
        Renders a bounded project coverage summary.
    #>
    Param([hashtable] $Model)

    $builder = New-Object System.Text.StringBuilder
    $displayName = if (-not [string]::IsNullOrWhiteSpace("$($Model.ProjectName)")) {
        "$($Model.ProjectName)"
    }
    else {
        "$($Model.Project)"
    }
    [void]$builder.AppendLine("## Code coverage: $(ConvertTo-SafeCoverageText $displayName)")
    [void]$builder.AppendLine()

    Add-CoverageOverviewMarkdown -Builder $builder -Model $Model

    [void]$builder.AppendLine("### Application coverage")
    [void]$builder.AppendLine()
    Add-ApplicationCoverageTable -Builder $builder -Applications @($Model.Apps)
    [void]$builder.AppendLine()

    if ($Model.LineComplete) {
        Add-UncoveredObjectsMarkdown -Builder $builder -Lines $Model.Lines
    }
    return Limit-CoverageSummary -Summary $builder.ToString()
}

function New-RepositoryCoverageSummary {
    <#
    .SYNOPSIS
        Renders a bounded repository coverage summary.
    #>
    Param([hashtable] $Model)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine("## Repository code coverage")
    [void]$builder.AppendLine()
    Add-CoverageOverviewMarkdown -Builder $builder -Model $Model
    [void]$builder.AppendLine("### Projects")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Project | Build mode | Status | Line rate |")
    [void]$builder.AppendLine("| :-- | :-- | :-- | --: |")
    foreach ($projectModel in @($Model.Projects)) {
        $status = if ($projectModel.LineComplete) {
            "complete"
        }
        else {
            "incomplete"
        }
        $lineRate = "-"
        if ($projectModel.LineComplete) {
            $lineMetrics = Get-CoverageMetrics $projectModel.Lines
            if ($lineMetrics.Total -gt 0) {
                $lineRate = "$($lineMetrics.Percentage.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture))%"
            }
        }
        $projectDisplay = if (-not [string]::IsNullOrWhiteSpace("$($projectModel.ProjectName)")) {
            "$($projectModel.ProjectName)"
        }
        else {
            "$($projectModel.Project)"
        }
        [void]$builder.AppendLine("| $(ConvertTo-SafeCoverageText $projectDisplay) | $(ConvertTo-SafeCoverageText $projectModel.BuildMode) | $status | $lineRate |")
    }
    [void]$builder.AppendLine()

    [void]$builder.AppendLine("### Application coverage")
    [void]$builder.AppendLine()
    Add-ApplicationCoverageTable -Builder $builder -Applications @($Model.Apps) -IncludeProject
    [void]$builder.AppendLine()

    if ($Model.LineComplete) {
        Add-UncoveredObjectsMarkdown -Builder $builder -Lines $Model.Lines
    }
    return Limit-CoverageSummary -Summary $builder.ToString()
}

Export-ModuleMember -Function ConvertTo-SafeCoverageText,
    Limit-CoverageSummary, Test-CodeCoverageSummaryRequested,
    Get-ProjectCoverageModel, Get-RepositoryCoverageModel,
    Resolve-CoverageObjectAttribution,
    Get-CoverageMetrics, New-ProjectCoverageSummary, New-RepositoryCoverageSummary
