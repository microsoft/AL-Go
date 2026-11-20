$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageAggregateFormat.psm1" -Resolve) `
    -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
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

function ConvertTo-SafeCoverageText {
    <#
    .SYNOPSIS
        Escapes an untrusted value for Markdown and embedded HTML.
    .PARAMETER Value
        Value to convert to safe single-line text.
    .PARAMETER MaximumLength
        Maximum output length before truncation.
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

function Test-CodeCoverageSummaryRequested {
    <#
    .SYNOPSIS
        Tests whether project settings request the supplied summary scope.
    .PARAMETER Settings
        Analyzed AL-Go settings containing useSeparateTestAction.
    .PARAMETER Scope
        Summary scope to test.
    #>
    Param(
        [hashtable] $Settings,
        [ValidateSet("project", "repository")]
        [string] $Scope
    )

    $requested = "$($Settings.useSeparateTestAction.codeCoverageSummary)".ToLowerInvariant()
    return $requested -eq "both" -or $requested -eq $Scope
}

function Read-CoverageJson {
    <#
    .SYNOPSIS
        Reads a coverage JSON object without throwing for invalid content.
    .PARAMETER Path
        Path to the JSON file.
    .PARAMETER Kind
        Display name used in an invalid-JSON reason.
    #>
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
    <#
    .SYNOPSIS
        Normalizes a project path for coverage-dimension matching.
    .PARAMETER Value
        Project path or dimension value to normalize.
    #>
    Param([AllowEmptyString()][string] $Value)
    return $Value.Replace('\', '/').Trim('/').ToLowerInvariant()
}

function Get-CoverageStatusFiles {
    <#
    .SYNOPSIS
        Finds coverage status manifests beneath a file or directory path.
    .PARAMETER CoveragePath
        Coverage status file or directory to search recursively.
    #>
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
    <#
    .SYNOPSIS
        Normalizes portable source-root details from a coverage status manifest.
    .PARAMETER Status
        Coverage status manifest containing sourceRootDetails.
    #>
    Param([hashtable] $Status)

    return @(
        foreach ($detail in @(Get-CoverageArray $Status.sourceRootDetails)) {
            $path = "$($detail.path)".Trim().Replace('\', '/').Trim('/')
            @{
                Path = $path
                Identity = $path.ToLowerInvariant()
                Kind = "$($detail.kind)".ToLowerInvariant()
                AppId = "$($detail.appId)"
                AppName = "$($detail.appName)"
            }
        }
    )
}

function New-CoverageApplicationModels {
    <#
    .SYNOPSIS
        Creates empty application coverage models for regular source roots.
    .PARAMETER SourceRootDetails
        Normalized source-root details from the coverage status manifest.
    #>
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
            RootIdentity = "$($detail.Identity)"
            AppId = "$($detail.AppId)"
            AppName = $appName
            Lines = @{}
        }
    }
    return @($apps)
}

function Merge-CoverageLine {
    <#
    .SYNOPSIS
        Merges one executable-line fact using covered-wins semantics.
    .PARAMETER Lines
        Destination dictionary of semantic line facts.
    .PARAMETER Key
        Semantic line identity.
    .PARAMETER Covered
        Whether the line was covered in the contributing aggregate.
    #>
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
    <#
    .SYNOPSIS
        Creates an empty project coverage model for an expected dimension.
    .PARAMETER Project
        Repository-relative project path.
    .PARAMETER ProjectName
        Project display name.
    .PARAMETER BuildMode
        Build mode associated with the project dimension.
    #>
    Param(
        [string] $Project,
        [string] $ProjectName,
        [string] $BuildMode
    )

    return @{
        Reasons = @()
        Diagnostics = @()
        IncompleteRuns = @()
        Project = $Project
        ProjectName = $ProjectName
        BuildMode = $BuildMode
        Apps = @()
        Lines = @{}
    }
}

function Get-ProjectCoverageModelFromStatus {
    <#
    .SYNOPSIS
        Builds a project coverage model from one status manifest and aggregate.
    .PARAMETER StatusPath
        Path to the coverage-status.json manifest.
    #>
    Param([string] $StatusPath)

    $model = New-EmptyProjectCoverageModel -Project "." -ProjectName "" -BuildMode ""
    $statusJson = Read-CoverageJson -Path $StatusPath -Kind "Coverage status"
    if (-not $statusJson.Valid) {
        $model.Reasons = @($statusJson.Reason)
        return $model
    }

    $status = $statusJson.Data
    foreach ($property in @("project", "projectName", "buildMode", "sourceRootDetails", "runs")) {
        if (-not $status.Contains($property)) {
            $model.Reasons = @("Coverage status is missing required data.")
            return $model
        }
    }

    $model.Project = "$($status.project)"
    $model.ProjectName = "$($status.projectName)"
    $model.BuildMode = "$($status.buildMode)"
    $sourceRootDetails = @(Get-CoverageSourceRootDetails -Status $status)
    $model.Apps = @(New-CoverageApplicationModels -SourceRootDetails $sourceRootDetails)
    $reasons = @()

    $aggregateResult = $null
    if (-not $status.Contains("aggregate")) {
        $reasons += "The published code coverage aggregate is missing."
    }
    else {
        try {
            if ("$($status.aggregate)" -cne "coverage-aggregate.bin.gz") {
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

    $statusRuns = @(Get-CoverageArray $status.runs)
    foreach ($run in $statusRuns) {
        $appName = "$($run.appName)"
        $state = "$($run.state)".ToLowerInvariant()
        $diagnostics = @(Get-CoverageArray $run.diagnostics | ForEach-Object { "$_" })
        if ($state -notin @("complete", "incomplete")) {
            $reasons += "$appName`: Run state is $state."
        }
        if ($state -eq "incomplete") {
            $model.IncompleteRuns += $appName
        }
        $model.Diagnostics += $diagnostics
    }
    if ($statusRuns.Count -eq 0) {
        $reasons += "Coverage status contains no test-app runs."
    }

    $model.Reasons = @($reasons | Select-Object -Unique)
    $model.Diagnostics = @($model.Diagnostics | Select-Object -Unique)
    $model.IncompleteRuns = @($model.IncompleteRuns | Select-Object -Unique)
    foreach ($app in $model.Apps) {
        foreach ($key in $app.Lines.Keys) {
            Merge-CoverageLine -Lines $model.Lines -Key "$key" `
                -Covered ([bool]$app.Lines[$key])
        }
    }
    return $model
}

function Get-ProjectCoverageModel {
    <#
    .SYNOPSIS
        Builds the project aggregate without throwing for incomplete coverage data.
    .PARAMETER CoveragePath
        Coverage status file or directory for the project.
    .PARAMETER Project
        Project path used when no unique status manifest is available.
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
    <#
    .SYNOPSIS
        Extracts repository-summary coverage dimensions from build-order JSON.
    .PARAMETER BuildOrderJson
        Serialized build-order entries produced by DetermineProjectsToBuild.
    #>
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
    <#
    .SYNOPSIS
        Combines project application models into repository application models.
    .PARAMETER ProjectModels
        Project coverage models to combine.
    #>
    Param([object[]] $ProjectModels)

    $applications = @{}
    foreach ($projectModel in $ProjectModels) {
        $projectIdentity = ConvertTo-CoverageDimensionIdentity "$($projectModel.Project)"
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
                    Lines = @{}
                }
            }
            $application = $applications[$key]
            foreach ($factKey in @($projectApp.Lines.Keys)) {
                Merge-CoverageLine -Lines $application.Lines -Key "$factKey" `
                    -Covered ([bool]$projectApp.Lines[$factKey])
            }
        }
    }

    return @($applications.Values)
}

function Get-RepositoryCoverageModel {
    <#
    .SYNOPSIS
        Builds a repository aggregate from expected build dimensions and downloaded artifacts.
    .PARAMETER CoveragePath
        Directory containing downloaded project coverage artifacts.
    .PARAMETER BuildOrderJson
        Build-order JSON used to identify expected coverage dimensions.
    #>
    Param(
        [string] $CoveragePath,
        [string] $BuildOrderJson
    )

    $repositoryModel = @{
        Reasons = @()
        Diagnostics = @()
        IncompleteRuns = @()
        Projects = @()
        Apps = @()
        Lines = @{}
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
    $reasons = @()
    foreach ($statusPath in @(Get-CoverageStatusFiles -CoveragePath $CoveragePath)) {
        $statusJson = Read-CoverageJson -Path $statusPath -Kind "Coverage status"
        if (-not $statusJson.Valid -or -not $statusJson.Data.Contains("project") -or
            -not $statusJson.Data.Contains("buildMode")) {
            $reasons += "A downloaded coverage status artifact is unreadable."
            continue
        }
        $statusEntries += @{
            Path = $statusPath
            Project = "$($statusJson.Data.project)"
            BuildMode = "$($statusJson.Data.buildMode)"
        }
    }

    $projectModels = @()
    foreach ($dimension in $dimensions) {
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
            continue
        }

        $projectModel = Get-ProjectCoverageModelFromStatus -StatusPath $statusMatches[0].Path
        $projectModels += $projectModel
        foreach ($reason in $projectModel.Reasons) {
            $reasons += "$($projectModel.Project) [$($projectModel.BuildMode)]: $reason"
        }
        $repositoryModel.Diagnostics += $projectModel.Diagnostics
        foreach ($runName in $projectModel.IncompleteRuns) {
            $repositoryModel.IncompleteRuns += "$($projectModel.Project) [$($projectModel.BuildMode)]: $runName"
        }
    }

    $repositoryModel.Projects = @($projectModels)
    $repositoryModel.Apps = @(Get-RepositoryApplications -ProjectModels $projectModels)
    $repositoryModel.Reasons = @($reasons | Select-Object -Unique)
    $repositoryModel.Diagnostics = @($repositoryModel.Diagnostics | Select-Object -Unique)
    $repositoryModel.IncompleteRuns = @($repositoryModel.IncompleteRuns | Select-Object -Unique)
    foreach ($projectModel in $projectModels) {
        foreach ($key in @($projectModel.Lines.Keys)) {
            Merge-CoverageLine -Lines $repositoryModel.Lines -Key "$key" `
                -Covered ([bool]$projectModel.Lines[$key])
        }
    }
    return $repositoryModel
}

function Get-CoverageMetrics {
    <#
    .SYNOPSIS
        Calculates covered, uncovered, total, and percentage values for semantic facts.
    .PARAMETER Facts
        Dictionary whose Boolean values indicate covered lines.
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
    .PARAMETER ObjectType
        Numeric Business Central object type.
    .PARAMETER ObjectId
        Business Central object ID.
    .PARAMETER SourcePath
        Repository-relative source path used to derive the object name.
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
    }
}

function Get-UncoveredObjectRows {
    <#
    .SYNOPSIS
        Returns the ten objects with the most uncovered executable lines.
    .PARAMETER Lines
        Semantic line facts keyed by source path, object type, object ID, and line number.
    #>
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
    <#
    .SYNOPSIS
        Appends one formatted coverage metric to a Markdown summary.
    .PARAMETER Builder
        Summary string builder to update.
    .PARAMETER Label
        Metric display label.
    .PARAMETER Metrics
        Coverage metrics returned by Get-CoverageMetrics.
    .PARAMETER DenominatorName
        Label for the total facts.
    .PARAMETER UncoveredName
        Label for uncovered facts.
    #>
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
    <#
    .SYNOPSIS
        Appends availability, line coverage, and diagnostic details to a summary.
    .PARAMETER Builder
        Summary string builder to update.
    .PARAMETER Model
        Project or repository coverage model.
    #>
    Param(
        [System.Text.StringBuilder] $Builder,
        [hashtable] $Model
    )

    if ($Model.Reasons.Count -gt 0) {
        [void]$Builder.AppendLine("> [!WARNING]")
        [void]$Builder.AppendLine("> Coverage is unavailable because required coverage data is missing or invalid.")
        foreach ($reason in @($Model.Reasons | Select-Object -Unique | Select-Object -First 20)) {
            [void]$Builder.AppendLine("> - $(ConvertTo-SafeCoverageText "$reason")")
        }
        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine("**Line coverage:** unavailable")
        [void]$Builder.AppendLine()
    }
    else {
        Add-CoverageMetricMarkdown -Builder $Builder -Label "Line" `
            -Metrics (Get-CoverageMetrics $Model.Lines) `
            -DenominatorName "executable lines" -UncoveredName "uncovered"
    }

    if ($Model.IncompleteRuns.Count -gt 0) {
        [void]$Builder.AppendLine("> [!WARNING]")
        [void]$Builder.AppendLine("> AlTool reported globally incomplete coverage for these runs. Available line facts are included:")
        foreach ($runName in @($Model.IncompleteRuns | Select-Object -Unique | Select-Object -First 20)) {
            [void]$Builder.AppendLine("> - $(ConvertTo-SafeCoverageText "$runName")")
        }
        [void]$Builder.AppendLine()
    }
    if ($Model.Diagnostics.Count -gt 0) {
        [void]$Builder.AppendLine("> [!WARNING]")
        [void]$Builder.AppendLine("> AlTool reported coverage diagnostics:")
        foreach ($diagnostic in @($Model.Diagnostics | Select-Object -Unique | Select-Object -First 20)) {
            [void]$Builder.AppendLine("> - $(ConvertTo-SafeCoverageText "$diagnostic")")
        }
        [void]$Builder.AppendLine()
    }
}

function Add-ApplicationCoverageTable {
    <#
    .SYNOPSIS
        Appends an application coverage table to a Markdown summary.
    .PARAMETER Builder
        Summary string builder to update.
    .PARAMETER Applications
        Application coverage models to render.
    .PARAMETER IncludeProject
        Includes a project column for repository summaries.
    .PARAMETER Unavailable
        Renders coverage values as unavailable.
    #>
    Param(
        [System.Text.StringBuilder] $Builder,
        [object[]] $Applications,
        [switch] $IncludeProject,
        [switch] $Unavailable
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
        if (-not $Unavailable) {
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
    <#
    .SYNOPSIS
        Appends the top uncovered objects section to a Markdown summary.
    .PARAMETER Builder
        Summary string builder to update.
    .PARAMETER Lines
        Semantic line facts used to rank uncovered objects.
    #>
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
        Renders a project coverage summary.
    .PARAMETER Model
        Project coverage model to render.
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
    Add-ApplicationCoverageTable -Builder $builder -Applications @($Model.Apps) `
        -Unavailable:($Model.Reasons.Count -gt 0)
    [void]$builder.AppendLine()

    if ($Model.Reasons.Count -eq 0) {
        Add-UncoveredObjectsMarkdown -Builder $builder -Lines $Model.Lines
    }
    return $builder.ToString()
}

function New-RepositoryCoverageSummary {
    <#
    .SYNOPSIS
        Renders a repository coverage summary.
    .PARAMETER Model
        Repository coverage model to render.
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
        $status = if ($projectModel.Reasons.Count -eq 0) {
            "available"
        }
        else {
            "unavailable"
        }
        $lineRate = "-"
        if ($projectModel.Reasons.Count -eq 0) {
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
    Add-ApplicationCoverageTable -Builder $builder -Applications @($Model.Apps) -IncludeProject `
        -Unavailable:($Model.Reasons.Count -gt 0)
    [void]$builder.AppendLine()

    if ($Model.Reasons.Count -eq 0) {
        Add-UncoveredObjectsMarkdown -Builder $builder -Lines $Model.Lines
    }
    return $builder.ToString()
}

Export-ModuleMember -Function ConvertTo-SafeCoverageText,
    Test-CodeCoverageSummaryRequested,
    Get-ProjectCoverageModel, Get-RepositoryCoverageModel,
    Resolve-CoverageObjectAttribution,
    Get-CoverageMetrics, New-ProjectCoverageSummary, New-RepositoryCoverageSummary
