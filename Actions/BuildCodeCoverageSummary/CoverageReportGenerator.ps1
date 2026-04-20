<#
.SYNOPSIS
    Generates coverage report markdown from Cobertura XML
.DESCRIPTION
    Parses Cobertura coverage XML and generates GitHub-flavored markdown
    summaries and detailed reports for display in job summaries.
#>

$statusHigh = " :green_circle:"      # >= 80%
$statusMedium = " :yellow_circle:"   # >= 50%
$statusLow = " :red_circle:"         # < 50%

$mdHelperPath = Join-Path -Path $PSScriptRoot -ChildPath "..\MarkDownHelper.psm1"
Import-Module $mdHelperPath

<#
.SYNOPSIS
    Gets a status icon based on coverage percentage
.PARAMETER Coverage
    Coverage percentage (0-100)
.OUTPUTS
    Status icon string
#>
function Get-CoverageStatusIcon {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Coverage
    )

    if ($Coverage -ge 80) { return $statusHigh }
    elseif ($Coverage -ge 50) { return $statusMedium }
    else { return $statusLow }
}

<#
.SYNOPSIS
    Formats a coverage percentage for display
.PARAMETER LineRate
    Line rate from Cobertura (0-1)
.OUTPUTS
    Formatted percentage string with icon
#>
function Format-CoveragePercent {
    param(
        [Parameter(Mandatory = $true)]
        [double]$LineRate
    )

    $percent = [math]::Round($LineRate * 100, 1)
    $icon = Get-CoverageStatusIcon -Coverage $percent
    return "$percent%$icon"
}

<#
.SYNOPSIS
    Creates a visual coverage bar using Unicode characters
.PARAMETER Coverage
    Coverage percentage (0-100)
.PARAMETER Width
    Bar width in characters (default 10)
.OUTPUTS
    Coverage bar string
#>
function New-CoverageBar {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Coverage,

        [Parameter(Mandatory = $false)]
        [int]$Width = 10
    )

    $filled = [math]::Floor($Coverage / 100 * $Width)
    $empty = $Width - $filled

    # Using ASCII-compatible characters for GitHub
    $bar = ("#" * $filled) + ("-" * $empty)
    return "``[$bar]``"
}

<#
.SYNOPSIS
    Extracts Area and Module paths from a filename
.PARAMETER Filename
    Source file path (e.g., "src/System Application/App/Email/src/Email.Codeunit.al")
.PARAMETER AppRoots
    Optional array of known app root paths (relative, forward-slash separated).
    When provided, the area is the matching app root and the module is the
    first subdirectory under it. Falls back to depth-based heuristic if empty.
.OUTPUTS
    Hashtable with Area and Module paths
#>
function Get-ModuleFromFilename {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Filename,

        [Parameter(Mandatory = $false)]
        [string[]]$AppRoots = @()
    )

    $normalizedFilename = $Filename.Replace('\', '/')

    # Try to match against known app roots (longest match first)
    if ($AppRoots.Count -gt 0) {
        $matchedRoot = $AppRoots | Sort-Object { $_.Length } -Descending | Where-Object {
            $normalizedFilename.StartsWith($_.Replace('\', '/') + '/', [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1

        if ($matchedRoot) {
            $area = $matchedRoot.Replace('\', '/')
            $remainder = $normalizedFilename.Substring($area.Length + 1)
            $parts = $remainder -split '/'
            $module = if ($parts.Count -ge 1 -and $parts[0]) { "$area/$($parts[0])" } else { $area }
            return @{ Area = $area; Module = $module }
        }
    }

    # Fallback: use path depth heuristic
    $parts = $normalizedFilename -split '/'

    $area = if ($parts.Count -ge 3) {
        "$($parts[0])/$($parts[1])/$($parts[2])"
    } else {
        $normalizedFilename
    }

    $module = if ($parts.Count -ge 4) {
        "$($parts[0])/$($parts[1])/$($parts[2])/$($parts[3])"
    } else {
        $area
    }

    return @{
        Area   = $area
        Module = $module
    }
}

<#
.SYNOPSIS
    Aggregates coverage data by module and area
.PARAMETER Coverage
    Coverage data from Read-CoberturaFile
.OUTPUTS
    Hashtable with AreaData containing module aggregations
#>
function Get-ModuleCoverageData {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Coverage,

        [Parameter(Mandatory = $false)]
        [string[]]$AppRoots = @()
    )

    $moduleData = @{}

    foreach ($package in $Coverage.Packages) {
        foreach ($class in $package.Classes) {
            $paths = Get-ModuleFromFilename -Filename $class.Filename -AppRoots $AppRoots
            $module = $paths.Module
            $area = $paths.Area

            if (-not $moduleData.ContainsKey($module)) {
                $moduleData[$module] = @{
                    Area         = $area
                    ModuleName   = if ($module -ne $area) { $module.Replace("$area/", "") } else { $module }
                    TotalLines   = 0
                    CoveredLines = 0
                    Objects      = 0
                }
            }

            $moduleData[$module].Objects++
            $moduleData[$module].TotalLines += $class.LinesTotal
            $moduleData[$module].CoveredLines += $class.LinesCovered
        }
    }

    # Group modules by area
    $areaData = @{}
    foreach ($mod in $moduleData.Keys) {
        $area = $moduleData[$mod].Area
        if (-not $areaData.ContainsKey($area)) {
            $areaData[$area] = @{
                Modules      = @{}
                AllZero      = $true
                TotalLines   = 0
                CoveredLines = 0
                Objects      = 0
            }
        }
        $areaData[$area].Modules[$mod] = $moduleData[$mod]
        $areaData[$area].TotalLines += $moduleData[$mod].TotalLines
        $areaData[$area].CoveredLines += $moduleData[$mod].CoveredLines
        $areaData[$area].Objects += $moduleData[$mod].Objects
        if ($moduleData[$mod].CoveredLines -gt 0) {
            $areaData[$area].AllZero = $false
        }
    }

    return $areaData
}

<#
.SYNOPSIS
    Parses Cobertura XML and returns coverage data
.PARAMETER CoverageFile
    Path to the Cobertura XML file
.OUTPUTS
    Hashtable with overall stats and per-class coverage
#>
function Read-CoberturaFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CoverageFile
    )

    if (-not (Test-Path $CoverageFile)) {
        throw "Coverage file not found: $CoverageFile"
    }

    [xml]$xml = Get-Content -Path $CoverageFile -Encoding UTF8

    $coverage = $xml.coverage

    # Use GetAttribute() to safely read optional XML attributes (avoids errors under Set-StrictMode -Version 2.0)
    $lineRateStr = $coverage.GetAttribute('line-rate')
    $branchRateStr = $coverage.GetAttribute('branch-rate')
    $linesCoveredStr = $coverage.GetAttribute('lines-covered')
    $linesValidStr = $coverage.GetAttribute('lines-valid')

    $result = @{
        LineRate       = if ($lineRateStr) { [double]$lineRateStr } else { 0.0 }
        BranchRate     = if ($branchRateStr) { [double]$branchRateStr } else { 0.0 }
        LinesCovered   = if ($linesCoveredStr) { [int]$linesCoveredStr } else { 0 }
        LinesValid     = if ($linesValidStr) { [int]$linesValidStr } else { 0 }
        Timestamp      = $coverage.GetAttribute('timestamp')
        Packages       = @()
    }

    # Handle empty packages element (strict mode compatible)
    $packagesNode = $coverage.SelectSingleNode('packages')
    if (-not $packagesNode -or -not $packagesNode.HasChildNodes) {
        return $result
    }

    foreach ($package in $packagesNode.package) {
        $pkgLineRateStr = $package.GetAttribute('line-rate')
        $packageData = @{
            Name       = $package.name
            LineRate   = if ($pkgLineRateStr) { [double]$pkgLineRateStr } else { 0.0 }
            Classes    = @()
        }

        # Handle empty classes element (strict mode compatible)
        $classesNode = $package.SelectSingleNode('classes')
        if (-not $classesNode -or -not $classesNode.HasChildNodes) {
            $result.Packages += $packageData
            continue
        }

        foreach ($class in $classesNode.class) {
            $methods = @()

            # Handle empty methods element (strict mode compatible)
            $methodsNode = $class.SelectSingleNode('methods')
            if ($methodsNode -and $methodsNode.HasChildNodes) {
                foreach ($method in $methodsNode.method) {
                    # Handle empty lines element in method (strict mode compatible)
                    $methodLinesNode = $method.SelectSingleNode('lines')
                    $methodLines = @()
                    if ($methodLinesNode -and $methodLinesNode.HasChildNodes) {
                        $methodLines = @($methodLinesNode.line)
                    }
                    $methodCovered = @($methodLines | Where-Object { [int]$_.hits -gt 0 }).Count
                    $methodTotal = $methodLines.Count

                    $methodLineRateStr = $method.GetAttribute('line-rate')
                    $methods += @{
                        Name        = $method.name
                        LineRate    = if ($methodLineRateStr) { [double]$methodLineRateStr } else { 0.0 }
                        LinesCovered = $methodCovered
                        LinesTotal  = $methodTotal
                    }
                }
            }

            # Handle lines element (strict mode compatible)
            $linesNode = $class.SelectSingleNode('lines')
            $classLines = @()
            if ($linesNode -and $linesNode.HasChildNodes) {
                $classLines = @($linesNode.line)
            }
            $classCovered = @($classLines | Where-Object { [int]$_.hits -gt 0 }).Count
            $classTotal = $classLines.Count

            $classLineRateStr = $class.GetAttribute('line-rate')
            $packageData.Classes += @{
                Name         = $class.name
                Filename     = $class.filename
                LineRate     = if ($classLineRateStr) { [double]$classLineRateStr } else { 0.0 }
                LinesCovered = $classCovered
                LinesTotal   = $classTotal
                Methods      = $methods
                Lines        = $classLines
            }
        }

        $result.Packages += $packageData
    }

    # Compute LinesCovered/LinesValid from parsed data when root attributes were missing
    if (-not $linesCoveredStr -or -not $linesValidStr) {
        $computedCovered = 0
        $computedValid = 0
        foreach ($pkg in $result.Packages) {
            foreach ($cls in $pkg.Classes) {
                $computedCovered += $cls.LinesCovered
                $computedValid += $cls.LinesTotal
            }
        }
        $result.LinesCovered = $computedCovered
        $result.LinesValid = $computedValid
    }

    return $result
}

<#
.SYNOPSIS
    Generates markdown summary from coverage data
.PARAMETER CoverageFile
    Path to the Cobertura XML file
.OUTPUTS
    Hashtable with SummaryMD and DetailsMD strings
#>
function Get-CoverageSummaryMD {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CoverageFile
    )

    try {
        $coverage = Read-CoberturaFile -CoverageFile $CoverageFile
    }
    catch {
        Write-Host "Error reading coverage file: $_"
        return @{
            SummaryMD = ""
            DetailsMD = ""
        }
    }

    # Try to read stats JSON for external code info
    $statsFile = [System.IO.Path]::ChangeExtension($CoverageFile, '.stats.json')
    $stats = $null
    if (Test-Path $statsFile) {
        try {
            $stats = Get-Content -Path $statsFile -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            Write-Host "Warning: Could not read stats file: $_"
        }
    }

    $summarySb = [System.Text.StringBuilder]::new()
    $detailsSb = [System.Text.StringBuilder]::new()

    # Overall summary
    $overallPercent = [math]::Round($coverage.LineRate * 100, 1)
    $overallIcon = Get-CoverageStatusIcon -Coverage $overallPercent
    $overallBar = New-CoverageBar -Coverage $overallPercent -Width 20

    $summarySb.AppendLine("### Overall Coverage: $overallPercent%$overallIcon") | Out-Null
    $summarySb.AppendLine("") | Out-Null
    $summarySb.AppendLine("$overallBar **$($coverage.LinesCovered)** of **$($coverage.LinesValid)** lines covered") | Out-Null
    $summarySb.AppendLine("") | Out-Null

    # External code section (code executed but no source available)
    # Safely check for property existence (strict mode compatible)
    $hasExcludedStats = $stats -and ($stats | Get-Member -Name 'ExcludedObjectCount' -MemberType NoteProperty) -and $stats.ExcludedObjectCount -gt 0
    if ($hasExcludedStats) {
        $excludedLinesExecuted = if ($stats | Get-Member -Name 'ExcludedLinesExecuted' -MemberType NoteProperty) { $stats.ExcludedLinesExecuted } else { 0 }
        $excludedTotalHits = if ($stats | Get-Member -Name 'ExcludedTotalHits' -MemberType NoteProperty) { $stats.ExcludedTotalHits } else { 0 }
        $summarySb.AppendLine("### External Code Executed") | Out-Null
        $summarySb.AppendLine("") | Out-Null
        $summarySb.AppendLine(":information_source: **$($stats.ExcludedObjectCount)** objects executed from external apps (no source available)") | Out-Null
        $summarySb.AppendLine("") | Out-Null
        $summarySb.AppendLine("- Lines executed: **$excludedLinesExecuted**") | Out-Null
        $summarySb.AppendLine("- Total hits: **$excludedTotalHits**") | Out-Null
        $summarySb.AppendLine("") | Out-Null
    }

    # Coverage threshold legend
    $summarySb.AppendLine("<sub>:green_circle: &ge;80% &nbsp; :yellow_circle: &ge;50% &nbsp; :red_circle: &lt;50%</sub>") | Out-Null
    $summarySb.AppendLine("") | Out-Null

    # Per-module coverage breakdown (aggregated from objects)
    if ($coverage.Packages.Count -gt 0) {
        # Use app source paths from stats for dynamic module detection
        $appRoots = @()
        $hasAppSourcePaths = $stats -and ($stats | Get-Member -Name 'AppSourcePaths' -MemberType NoteProperty) -and $stats.AppSourcePaths
        if ($hasAppSourcePaths) {
            $appRoots = @($stats.AppSourcePaths)
        }
        $areaData = Get-ModuleCoverageData -Coverage $coverage -AppRoots $appRoots

        # Separate areas into those with coverage and those without
        $areasWithCoverage = @($areaData.GetEnumerator() | Where-Object { -not $_.Value.AllZero } | Sort-Object { $_.Value.CoveredLines } -Descending)
        $areasWithoutCoverage = @($areaData.GetEnumerator() | Where-Object { $_.Value.AllZero } | Sort-Object { $_.Value.Objects } -Descending)

        # Build module-level table for areas with coverage (collapsible)
        if ($areasWithCoverage.Count -gt 0) {
            $totalModules = ($areasWithCoverage | ForEach-Object { $_.Value.Modules.Count } | Measure-Object -Sum).Sum
            $detailsSb.AppendLine("<details>") | Out-Null
            $detailsSb.AppendLine("<summary><b>Coverage by Module</b> ($($areasWithCoverage.Count) areas, $totalModules modules with coverage)</summary>") | Out-Null
            $detailsSb.AppendLine("") | Out-Null

            $headers = @("Module;left", "Coverage;right", "Lines;right", "Objects;right", "Bar;left")
            $rows = [System.Collections.ArrayList]@()

            foreach ($area in $areasWithCoverage) {
                # Add area header row
                $areaPct = if ($area.Value.TotalLines -gt 0) { [math]::Round($area.Value.CoveredLines / $area.Value.TotalLines * 100, 1) } else { 0 }
                $areaIcon = Get-CoverageStatusIcon -Coverage $areaPct
                $areaBar = New-CoverageBar -Coverage $areaPct -Width 10

                $areaRow = @(
                    "**$($area.Key)**",
                    "**$areaPct%$areaIcon**",
                    "**$($area.Value.CoveredLines)/$($area.Value.TotalLines)**",
                    "**$($area.Value.Objects)**",
                    $areaBar
                )
                $rows.Add($areaRow) | Out-Null

                # Add module rows (indented)
                $sortedModules = $area.Value.Modules.GetEnumerator() | Sort-Object { $_.Value.CoveredLines } -Descending
                foreach ($mod in $sortedModules) {
                    $modPct = if ($mod.Value.TotalLines -gt 0) { [math]::Round($mod.Value.CoveredLines / $mod.Value.TotalLines * 100, 1) } else { 0 }
                    $modIcon = Get-CoverageStatusIcon -Coverage $modPct
                    $modBar = New-CoverageBar -Coverage $modPct -Width 10

                    $modRow = @(
                        "&nbsp;&nbsp;&nbsp;&nbsp;$($mod.Value.ModuleName)",
                        "$modPct%$modIcon",
                        "$($mod.Value.CoveredLines)/$($mod.Value.TotalLines)",
                        "$($mod.Value.Objects)",
                        $modBar
                    )
                    $rows.Add($modRow) | Out-Null
                }
            }

            try {
                $table = Build-MarkdownTable -Headers $headers -Rows $rows
                $detailsSb.AppendLine($table) | Out-Null
            }
            catch {
                $detailsSb.AppendLine("<i>Failed to generate module coverage table</i>") | Out-Null
            }
            $detailsSb.AppendLine("") | Out-Null
            $detailsSb.AppendLine("</details>") | Out-Null
            $detailsSb.AppendLine("") | Out-Null
        }

        # Show collapsed areas (all 0% coverage) in a separate section
        if ($areasWithoutCoverage.Count -gt 0) {
            $detailsSb.AppendLine("<details>") | Out-Null
            $detailsSb.AppendLine("<summary><b>Areas with no coverage data</b> ($($areasWithoutCoverage.Count) areas)</summary>") | Out-Null
            $detailsSb.AppendLine("") | Out-Null
            $detailsSb.AppendLine("These areas had no lines executed during tests:") | Out-Null
            $detailsSb.AppendLine("") | Out-Null

            $zeroHeaders = @("Area;left", "Objects;right", "Lines;right")
            $zeroRows = [System.Collections.ArrayList]@()

            foreach ($area in $areasWithoutCoverage) {
                $zeroRow = @(
                    $area.Key,
                    $area.Value.Objects.ToString(),
                    $area.Value.TotalLines.ToString()
                )
                $zeroRows.Add($zeroRow) | Out-Null
            }

            try {
                $zeroTable = Build-MarkdownTable -Headers $zeroHeaders -Rows $zeroRows
                $detailsSb.AppendLine($zeroTable) | Out-Null
            }
            catch {
                $detailsSb.AppendLine("<i>Failed to generate table</i>") | Out-Null
            }

            $detailsSb.AppendLine("") | Out-Null
            $detailsSb.AppendLine("</details>") | Out-Null
        }

        $detailsSb.AppendLine("") | Out-Null
    }

    # External objects section (collapsible)
    # Use Get-Member to safely check if ExcludedObjects property exists (strict mode compatible)
    $hasExcludedObjects = $stats -and ($stats | Get-Member -Name 'ExcludedObjects' -MemberType NoteProperty) -and $stats.ExcludedObjects -and @($stats.ExcludedObjects).Count -gt 0
    if ($hasExcludedObjects) {
        $detailsSb.AppendLine("") | Out-Null
        $detailsSb.AppendLine("<details>") | Out-Null
        $detailsSb.AppendLine("<summary><b>External Objects Executed (no source available)</b></summary>") | Out-Null
        $detailsSb.AppendLine("") | Out-Null
        $detailsSb.AppendLine("These objects were executed during tests but their source code was not found in the workspace:") | Out-Null
        $detailsSb.AppendLine("") | Out-Null

        $extHeaders = @("Object Type;left", "Object ID;right", "Lines Executed;right", "Total Hits;right")
        $extRows = [System.Collections.ArrayList]@()

        foreach ($obj in ($stats.ExcludedObjects | Sort-Object -Property TotalHits -Descending)) {
            $extRow = @(
                $obj.ObjectType,
                $obj.ObjectId.ToString(),
                $obj.LinesExecuted.ToString(),
                $obj.TotalHits.ToString()
            )
            $extRows.Add($extRow) | Out-Null
        }

        try {
            $extTable = Build-MarkdownTable -Headers $extHeaders -Rows $extRows
            $detailsSb.AppendLine($extTable) | Out-Null
        }
        catch {
            $detailsSb.AppendLine("<i>Failed to generate external objects table</i>") | Out-Null
        }

        $detailsSb.AppendLine("") | Out-Null
        $detailsSb.AppendLine("</details>") | Out-Null
    }

    return @{
        SummaryMD = $summarySb.ToString()
        DetailsMD = $detailsSb.ToString()
    }
}
