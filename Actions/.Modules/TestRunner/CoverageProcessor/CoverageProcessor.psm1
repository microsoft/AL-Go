<#
.SYNOPSIS
    Main orchestrator for processing BC code coverage into Cobertura format
.DESCRIPTION
    Combines BCCoverageParser, ALSourceParser, and CoberturaFormatter to produce
    standardized coverage reports from BC code coverage .dat files.
#>

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

# Import sub-modules
$scriptPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
Import-Module (Join-Path $scriptPath "BCCoverageParser.psm1") -Force
Import-Module (Join-Path $scriptPath "ALSourceParser.psm1") -Force
Import-Module (Join-Path $scriptPath "CoberturaFormatter.psm1") -Force

# Helper to safely check for a property on either a hashtable or PSCustomObject under strict mode
function Test-PropertyExists {
    param($InputObject, [string]$PropertyName)
    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [hashtable]) { return $InputObject.ContainsKey($PropertyName) }
    return $null -ne $InputObject.PSObject.Properties[$PropertyName]
}

<#
.SYNOPSIS
    Processes BC code coverage files and generates Cobertura XML output
.PARAMETER CoverageFilePath
    Path to the BC coverage .dat file
.PARAMETER SourcePath
    Path to the source code directory (for file/method mapping)
.PARAMETER OutputPath
    Path where the Cobertura XML file should be written
.PARAMETER AppJsonPath
    Optional path to app.json for app metadata
.OUTPUTS
    Returns coverage statistics object
#>
function Convert-BCCoverageToCobertura {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CoverageFilePath,

        [Parameter(Mandatory = $false)]
        [string]$SourcePath = "",

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$AppJsonPath = "",

        [Parameter(Mandatory = $false)]
        [string[]]$AppSourcePaths = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePatterns = @()
    )

    Write-Host "Converting BC coverage to Cobertura format..."
    Write-Host "  Coverage file: $CoverageFilePath"
    Write-Host "  Source path: $SourcePath"
    Write-Host "  Output path: $OutputPath"

    # Step 1: Parse the coverage file
    Write-Host "`nStep 1: Parsing coverage data..."
    $coverageEntries = Read-BCCoverageFile -Path $CoverageFilePath

    if ($coverageEntries.Count -eq 0) {
        Write-Warning "No coverage entries found in file"
        return $null
    }

    # Step 2: Group coverage by object
    Write-Host "`nStep 2: Grouping coverage by object..."
    $groupedCoverage = Group-CoverageByObject -CoverageEntries $coverageEntries
    Write-Host "  Found $($groupedCoverage.Count) unique objects"

    # Step 3: Load app metadata if available
    $appInfo = $null
    if ($AppJsonPath -and (Test-Path $AppJsonPath)) {
        Write-Host "`nStep 3: Loading app metadata..."
        $appInfo = Read-AppJson -AppJsonPath $AppJsonPath
        if ($appInfo) {
            Write-Host "  App: $($appInfo.Name) v$($appInfo.Version)"
        }
    }
    elseif ($SourcePath) {
        # Try to find app.json in source path
        $autoAppJson = Join-Path $SourcePath "app.json"
        if (Test-Path $autoAppJson) {
            Write-Host "`nStep 3: Loading app metadata from source path..."
            $appInfo = Read-AppJson -AppJsonPath $autoAppJson
            if ($appInfo) {
                Write-Host "  App: $($appInfo.Name) v$($appInfo.Version)"
            }
        }
    }

    # Step 4: Map source files if source path provided
    $objectMap = @{}
    $excludedObjectsData = [System.Collections.Generic.List[object]]::new()

    if ($SourcePath -and (Test-Path $SourcePath)) {
        Write-Host "`nStep 4: Mapping source files..."
        $objectMap = Get-ALObjectMap -SourcePath $SourcePath -AppSourcePaths $AppSourcePaths -ExcludePatterns $ExcludePatterns

        # Filter coverage to only include objects from user's source files
        # This excludes Microsoft base app objects
        $filteredCoverage = @{}

        foreach ($key in $groupedCoverage.Keys) {
            if ($objectMap.ContainsKey($key)) {
                $filteredCoverage[$key] = $groupedCoverage[$key]
                $filteredCoverage[$key].SourceInfo = $objectMap[$key]
            } else {
                # Track excluded object details for reporting
                $objData = $groupedCoverage[$key]
                $linesExecuted = @($objData.Lines | Where-Object { $_.IsCovered }).Count
                $excludedObjectsData.Add([PSCustomObject]@{
                    ObjectType    = $objData.ObjectType
                    ObjectId      = $objData.ObjectId
                    LinesExecuted = $linesExecuted
                    TotalHits     = ($objData.Lines | Measure-Object -Property Hits -Sum).Sum
                })
            }
        }

        Write-Host "  Found $($objectMap.Count) objects in source files"
        Write-Host "  Matched $($filteredCoverage.Count) objects with coverage data"
        if ($excludedObjectsData.Count -gt 0) {
            Write-Host "  Excluded $($excludedObjectsData.Count) objects (Microsoft/external)"
        }

        # Use filtered coverage going forward
        $groupedCoverage = $filteredCoverage

        # Add objects from source that have no coverage (not executed at all)
        foreach ($key in $objectMap.Keys) {
            if (-not $groupedCoverage.ContainsKey($key)) {
                # Object exists in source but has no coverage - add with empty lines
                $groupedCoverage[$key] = @{
                    ObjectType   = $objectMap[$key].ObjectType
                    ObjectTypeId = Get-ObjectTypeId $objectMap[$key].ObjectType
                    ObjectId     = $objectMap[$key].ObjectId
                    Lines        = @()
                    SourceInfo   = $objectMap[$key]
                }
            }
        }
    }

    # Step 5: Generate Cobertura XML
    Write-Host "`nStep 5: Generating Cobertura XML..."
    $coberturaXml = New-CoberturaDocument -CoverageData $groupedCoverage -SourcePath $SourcePath -AppInfo $appInfo

    # Step 6: Save output
    Write-Host "`nStep 6: Saving output..."
    Save-CoberturaFile -XmlDocument $coberturaXml -OutputPath $OutputPath

    # Calculate and return statistics
    # Always prefer source-based executable line count when available.
    # XMLport 130470 only exports covered lines, making Lines.Count inaccurate
    # as a denominator (it equals covered-line count, not total executable lines).
    # XMLport 130007 exports all executable lines, so Lines.Count would be correct,
    # but source-based count is still preferred for consistency.
    $totalExecutableLines = 0
    $coveredLines = 0

    foreach ($obj in $groupedCoverage.Values) {
        $objTotalLines = if ((Test-PropertyExists $obj 'SourceInfo') -and $obj.SourceInfo -and (Test-PropertyExists $obj.SourceInfo 'ExecutableLines') -and $obj.SourceInfo.ExecutableLines -gt 0) {
            $obj.SourceInfo.ExecutableLines
        } else {
            $obj.Lines.Count
        }

        $totalExecutableLines += $objTotalLines
        $coveredLines += @($obj.Lines | Where-Object { $_.IsCovered }).Count
    }

    $coveragePercent = if ($totalExecutableLines -gt 0) {
        [math]::Round(($coveredLines / $totalExecutableLines) * 100, 2)
    } else {
        0
    }

    # Calculate stats for excluded objects (external/base app code)
    $excludedLinesExecuted = 0
    $excludedTotalHits = 0
    if ($excludedObjectsData.Count -gt 0) {
        $excludedLinesExecuted = ($excludedObjectsData | Measure-Object -Property LinesExecuted -Sum).Sum
        $excludedTotalHits = ($excludedObjectsData | Measure-Object -Property TotalHits -Sum).Sum
    }

    $stats = [PSCustomObject]@{
        TotalLines           = $totalExecutableLines
        CoveredLines         = $coveredLines
        NotCoveredLines      = $totalExecutableLines - $coveredLines
        CoveragePercent      = $coveragePercent
        LineRate             = if ($totalExecutableLines -gt 0) { $coveredLines / $totalExecutableLines } else { 0 }
        ObjectCount          = $groupedCoverage.Count
        ExcludedObjectCount  = $excludedObjectsData.Count
        ExcludedLinesExecuted = $excludedLinesExecuted
        ExcludedTotalHits    = $excludedTotalHits
        ExcludedObjects      = $excludedObjectsData
        AppSourcePaths       = @($AppSourcePaths | ForEach-Object {
            # Store paths relative to SourcePath for portability
            $normalizedSrc = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\', '/')
            $normalizedApp = [System.IO.Path]::GetFullPath($_).TrimEnd('\', '/')
            if ($normalizedApp.StartsWith($normalizedSrc, [System.StringComparison]::OrdinalIgnoreCase)) {
                $normalizedApp.Substring($normalizedSrc.Length + 1).Replace('\', '/')
            } else { $normalizedApp.Replace('\', '/') }
        })
    }

    # Save extended stats to JSON file alongside Cobertura XML
    $statsOutputPath = [System.IO.Path]::ChangeExtension($OutputPath, '.stats.json')
    $stats | ConvertTo-Json -Depth 10 | Set-Content -Path $statsOutputPath -Encoding UTF8
    Write-Host "  Saved coverage stats to: $statsOutputPath"

    Write-Host "`n=== Coverage Summary (User Code Only) ==="
    Write-Host "  Objects:       $($stats.ObjectCount)"
    Write-Host "  Total lines:   $($stats.TotalLines)"
    Write-Host "  Covered lines: $($stats.CoveredLines)"
    Write-Host "  Coverage:      $($stats.CoveragePercent)%"
    if ($stats.ExcludedObjectCount -gt 0) {
        Write-Host "  --- External Code (no source) ---"
        Write-Host "  Excluded objects: $($stats.ExcludedObjectCount)"
        Write-Host "  Lines executed:   $($stats.ExcludedLinesExecuted)"
    }
    Write-Host "==========================================`n"

    return $stats
}

<#
.SYNOPSIS
    Processes multiple coverage files and merges into single Cobertura output
.PARAMETER CoverageFiles
    Array of paths to coverage .dat files
.PARAMETER SourcePath
    Path to the source code directory
.PARAMETER OutputPath
    Path where the merged Cobertura XML should be written
.PARAMETER AppJsonPath
    Optional path to app.json
.OUTPUTS
    Returns merged coverage statistics
#>
function Merge-BCCoverageToCobertura {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CoverageFiles,

        [Parameter(Mandatory = $false)]
        [string]$SourcePath = "",

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$AppJsonPath = "",

        [Parameter(Mandatory = $false)]
        [string[]]$AppSourcePaths = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePatterns = @()
    )

    Write-Host "Merging $($CoverageFiles.Count) coverage files..."

    $allEntries = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $CoverageFiles) {
        if (Test-Path $file) {
            Write-Host "  Reading: $file"
            $entries = Read-BCCoverageFile -Path $file
            $allEntries.AddRange(@($entries))
        }
        else {
            Write-Warning "Coverage file not found: $file"
        }
    }

    if ($allEntries.Count -eq 0) {
        Write-Warning "No coverage entries found in any file"
        return $null
    }

    # Merge entries by object+line (take max hits)
    $mergedEntries = @{}
    foreach ($entry in $allEntries) {
        $key = "$($entry.ObjectTypeId)_$($entry.ObjectId)_$($entry.LineNo)"

        if ($mergedEntries.ContainsKey($key)) {
            $existing = $mergedEntries[$key]
            # Accumulate hits and promote coverage status
            if ($entry.Hits -gt $existing.Hits) {
                $mergedEntries[$key].Hits = $entry.Hits
            }
            if ($entry.IsCovered -and -not $existing.IsCovered) {
                $mergedEntries[$key].IsCovered = $true
                $mergedEntries[$key].CoverageStatus = $entry.CoverageStatus
                $mergedEntries[$key].CoverageStatusName = $entry.CoverageStatusName
            }
        }
        else {
            $mergedEntries[$key] = $entry
        }
    }

    $coverageEntries = $mergedEntries.Values | Sort-Object ObjectTypeId, ObjectId, LineNo
    Write-Host "Merged to $($coverageEntries.Count) unique line entries"

    # Group and process
    $groupedCoverage = Group-CoverageByObject -CoverageEntries $coverageEntries

    # Load metadata
    $appInfo = $null
    if ($AppJsonPath -and (Test-Path $AppJsonPath)) {
        $appInfo = Read-AppJson -AppJsonPath $AppJsonPath
    }
    elseif ($SourcePath) {
        $autoAppJson = Join-Path $SourcePath "app.json"
        if (Test-Path $autoAppJson) {
            $appInfo = Read-AppJson -AppJsonPath $autoAppJson
        }
    }

    # Map sources and track excluded objects
    $excludedObjectsData = [System.Collections.Generic.List[object]]::new()
    if ($SourcePath -and (Test-Path $SourcePath)) {
        $objectMap = Get-ALObjectMap -SourcePath $SourcePath -AppSourcePaths $AppSourcePaths -ExcludePatterns $ExcludePatterns
        $filteredCoverage = @{}

        foreach ($key in $groupedCoverage.Keys) {
            if ($objectMap.ContainsKey($key)) {
                $filteredCoverage[$key] = $groupedCoverage[$key]
                $filteredCoverage[$key].SourceInfo = $objectMap[$key]
            } else {
                # Track excluded object details
                $objData = $groupedCoverage[$key]
                $linesExecuted = @($objData.Lines | Where-Object { $_.IsCovered }).Count
                $excludedObjectsData.Add([PSCustomObject]@{
                    ObjectType    = $objData.ObjectType
                    ObjectId      = $objData.ObjectId
                    LinesExecuted = $linesExecuted
                    TotalHits     = ($objData.Lines | Measure-Object -Property Hits -Sum).Sum
                })
            }
        }

        Write-Host "  Matched $($filteredCoverage.Count) objects with source"
        if ($excludedObjectsData.Count -gt 0) {
            Write-Host "  Excluded $($excludedObjectsData.Count) objects (Microsoft/external)"
        }
        $groupedCoverage = $filteredCoverage

        # Add objects from source that have no coverage (not executed at all)
        foreach ($key in $objectMap.Keys) {
            if (-not $groupedCoverage.ContainsKey($key)) {
                $groupedCoverage[$key] = @{
                    ObjectType   = $objectMap[$key].ObjectType
                    ObjectTypeId = Get-ObjectTypeId $objectMap[$key].ObjectType
                    ObjectId     = $objectMap[$key].ObjectId
                    Lines        = @()
                    SourceInfo   = $objectMap[$key]
                }
            }
        }
    }

    # Generate and save
    $coberturaXml = New-CoberturaDocument -CoverageData $groupedCoverage -SourcePath $SourcePath -AppInfo $appInfo
    Save-CoberturaFile -XmlDocument $coberturaXml -OutputPath $OutputPath

    # Calculate stats from filtered/grouped coverage (user code only), consistent with Convert-BCCoverageToCobertura
    # Always prefer source-based executable line count — see Convert-BCCoverageToCobertura for rationale
    $totalExecutableLines = 0
    $coveredLines = 0

    foreach ($obj in $groupedCoverage.Values) {
        $objTotalLines = if ((Test-PropertyExists $obj 'SourceInfo') -and $obj.SourceInfo -and (Test-PropertyExists $obj.SourceInfo 'ExecutableLines') -and $obj.SourceInfo.ExecutableLines -gt 0) {
            $obj.SourceInfo.ExecutableLines
        } else {
            $obj.Lines.Count
        }
        $totalExecutableLines += $objTotalLines
        $coveredLines += @($obj.Lines | Where-Object { $_.IsCovered }).Count
    }

    $coveragePercent = if ($totalExecutableLines -gt 0) {
        [math]::Round(($coveredLines / $totalExecutableLines) * 100, 2)
    } else {
        0
    }

    # Calculate stats for excluded objects (external/base app code)
    $excludedLinesExecuted = 0
    $excludedTotalHits = 0
    if ($excludedObjectsData.Count -gt 0) {
        $excludedLinesExecuted = ($excludedObjectsData | Measure-Object -Property LinesExecuted -Sum).Sum
        $excludedTotalHits = ($excludedObjectsData | Measure-Object -Property TotalHits -Sum).Sum
    }

    $stats = [PSCustomObject]@{
        TotalLines           = $totalExecutableLines
        CoveredLines         = $coveredLines
        NotCoveredLines      = $totalExecutableLines - $coveredLines
        CoveragePercent      = $coveragePercent
        LineRate             = if ($totalExecutableLines -gt 0) { $coveredLines / $totalExecutableLines } else { 0 }
        ObjectCount          = $groupedCoverage.Count
        ExcludedObjectCount  = $excludedObjectsData.Count
        ExcludedLinesExecuted = $excludedLinesExecuted
        ExcludedTotalHits    = $excludedTotalHits
        ExcludedObjects      = $excludedObjectsData
        AppSourcePaths       = @($AppSourcePaths | ForEach-Object {
            $normalizedSrc = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd('\', '/')
            $normalizedApp = [System.IO.Path]::GetFullPath($_).TrimEnd('\', '/')
            if ($normalizedApp.StartsWith($normalizedSrc, [System.StringComparison]::OrdinalIgnoreCase)) {
                $normalizedApp.Substring($normalizedSrc.Length + 1).Replace('\', '/')
            } else { $normalizedApp.Replace('\', '/') }
        })
    }

    # Save extended stats to JSON file
    $statsOutputPath = [System.IO.Path]::ChangeExtension($OutputPath, '.stats.json')
    $stats | ConvertTo-Json -Depth 10 | Set-Content -Path $statsOutputPath -Encoding UTF8
    Write-Host "  Saved coverage stats to: $statsOutputPath"

    Write-Host "`n=== Merged Coverage Summary (User Code Only) ==="
    Write-Host "  Objects:       $($stats.ObjectCount)"
    Write-Host "  Total lines:   $($stats.TotalLines)"
    Write-Host "  Covered lines: $($stats.CoveredLines)"
    Write-Host "  Coverage:      $($stats.CoveragePercent)%"
    if ($stats.ExcludedObjectCount -gt 0) {
        Write-Host "  --- External Code (no source) ---"
        Write-Host "  Excluded objects: $($stats.ExcludedObjectCount)"
        Write-Host "  Lines executed:   $($stats.ExcludedLinesExecuted)"
    }
    Write-Host "================================================`n"

    return $stats
}

<#
.SYNOPSIS
    Finds coverage files in a directory
.PARAMETER Directory
    Directory to search for coverage files
.PARAMETER Pattern
    File pattern to match (default: *.dat)
.OUTPUTS
    Array of file paths
#>
function Find-CoverageFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $false)]
        [string]$Pattern = "*.dat"
    )

    if (-not (Test-Path $Directory)) {
        Write-Warning "Directory not found: $Directory"
        return @()
    }

    $files = Get-ChildItem -Path $Directory -Filter $Pattern -File -Recurse
    return $files.FullName
}

<#
.SYNOPSIS
    Quick coverage summary without generating full Cobertura output
.PARAMETER CoverageFilePath
    Path to the coverage .dat file
.OUTPUTS
    Coverage statistics object
#>
function Get-BCCoverageSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CoverageFilePath
    )

    $entries = Read-BCCoverageFile -Path $CoverageFilePath
    $stats = Get-CoverageStatistics -CoverageEntries $entries

    # Add object breakdown
    $grouped = Group-CoverageByObject -CoverageEntries $entries
    $objectStats = @()

    foreach ($key in $grouped.Keys | Sort-Object) {
        $obj = $grouped[$key]
        $objEntries = $obj.Lines
        $objStats = Get-CoverageStatistics -CoverageEntries $objEntries

        $objectStats += [PSCustomObject]@{
            Object          = $key
            ObjectType      = $obj.ObjectType
            ObjectId        = $obj.ObjectId
            TotalLines      = $objStats.TotalLines
            CoveredLines    = $objStats.CoveredLines
            CoveragePercent = $objStats.CoveragePercent
        }
    }

    $stats | Add-Member -NotePropertyName "Objects" -NotePropertyValue $objectStats

    return $stats
}

Export-ModuleMember -Function @(
    'Convert-BCCoverageToCobertura',
    'Merge-BCCoverageToCobertura',
    'Find-CoverageFiles',
    'Get-BCCoverageSummary'
)
