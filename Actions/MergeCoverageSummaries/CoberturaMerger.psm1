<#
.SYNOPSIS
    Merges multiple Cobertura XML coverage files into a single consolidated report
.DESCRIPTION
    Reads cobertura.xml files from multiple build jobs, unions coverage data by
    filename+line, and produces a single merged cobertura.xml. For duplicate lines
    (same file, same line number), takes the maximum hits across all inputs.
#>

<#
.SYNOPSIS
    Merges multiple Cobertura XML files into one
.PARAMETER CoberturaFiles
    Array of paths to cobertura.xml files
.PARAMETER OutputPath
    Path where the merged cobertura.xml should be written
.OUTPUTS
    Merged coverage statistics object
#>
function Merge-CoberturaFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CoberturaFiles,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    Write-Host "Merging $($CoberturaFiles.Count) Cobertura files..."

    # Parse all files and collect line data per class
    # Key: filename -> line number -> { hits, branch }
    $classData = @{}    # filename -> @{ name, lines = @{} }
    $packageData = @{}  # package name -> set of filenames

    foreach ($file in $CoberturaFiles) {
        if (-not (Test-Path $file)) {
            Write-Warning "Cobertura file not found: $file"
            continue
        }

        Write-Host "  Reading: $file"
        [xml]$xml = Get-Content -Path $file -Encoding UTF8

        $packagesNode = $xml.coverage.SelectSingleNode('packages')
        if (-not $packagesNode -or -not $packagesNode.HasChildNodes) { continue }

        foreach ($package in $packagesNode.package) {
            $pkgName = $package.name

            $classesNode = $package.SelectSingleNode('classes')
            if (-not $classesNode -or -not $classesNode.HasChildNodes) { continue }

            foreach ($class in $classesNode.class) {
                $filename = $class.filename
                $className = $class.name

                if (-not $classData.ContainsKey($filename)) {
                    $classData[$filename] = @{
                        Name    = $className
                        Package = $pkgName
                        Lines   = @{}
                    }
                }

                # Track which package this class belongs to
                if (-not $packageData.ContainsKey($pkgName)) {
                    $packageData[$pkgName] = [System.Collections.Generic.HashSet[string]]::new()
                }
                $packageData[$pkgName].Add($filename) | Out-Null

                # Merge lines: take max hits for each line number
                $linesNode = $class.SelectSingleNode('lines')
                if ($linesNode -and $linesNode.HasChildNodes) {
                    foreach ($line in $linesNode.line) {
                        $lineNum = [int]$line.number
                        $hits = [int]$line.hits
                        $branch = $line.branch

                        if ($classData[$filename].Lines.ContainsKey($lineNum)) {
                            $existing = $classData[$filename].Lines[$lineNum]
                            if ($hits -gt $existing.Hits) {
                                $classData[$filename].Lines[$lineNum].Hits = $hits
                            }
                        } else {
                            $classData[$filename].Lines[$lineNum] = @{
                                Hits   = $hits
                                Branch = $branch
                            }
                        }
                    }
                }
            }
        }
    }

    Write-Host "  Merged to $($classData.Count) unique classes"

    # Build merged XML
    $xml = New-Object System.Xml.XmlDocument
    $declaration = $xml.CreateXmlDeclaration("1.0", "UTF-8", $null)
    $xml.AppendChild($declaration) | Out-Null

    # Calculate overall stats
    $totalLines = 0
    $coveredLines = 0

    foreach ($cls in $classData.Values) {
        $totalLines += $cls.Lines.Count
        $coveredLines += @($cls.Lines.Values | Where-Object { $_.Hits -gt 0 }).Count
    }

    $lineRate = if ($totalLines -gt 0) { [math]::Round($coveredLines / $totalLines, 4) } else { 0 }

    $coverage = $xml.CreateElement("coverage")
    $coverage.SetAttribute("line-rate", $lineRate.ToString())
    $coverage.SetAttribute("branch-rate", "0")
    $coverage.SetAttribute("lines-covered", $coveredLines.ToString())
    $coverage.SetAttribute("lines-valid", $totalLines.ToString())
    $coverage.SetAttribute("branches-covered", "0")
    $coverage.SetAttribute("branches-valid", "0")
    $coverage.SetAttribute("complexity", "0")
    $coverage.SetAttribute("version", "1.0")
    $coverage.SetAttribute("timestamp", [DateTimeOffset]::Now.ToUnixTimeSeconds().ToString())
    $xml.AppendChild($coverage) | Out-Null

    $sources = $xml.CreateElement("sources")
    $source = $xml.CreateElement("source")
    $source.InnerText = "."
    $sources.AppendChild($source) | Out-Null
    $coverage.AppendChild($sources) | Out-Null

    $packagesElement = $xml.CreateElement("packages")
    $coverage.AppendChild($packagesElement) | Out-Null

    # Group classes by package
    $packageGroups = @{}
    foreach ($filename in $classData.Keys) {
        $pkgName = $classData[$filename].Package
        if (-not $packageGroups.ContainsKey($pkgName)) {
            $packageGroups[$pkgName] = @()
        }
        $packageGroups[$pkgName] += $filename
    }

    foreach ($pkgName in $packageGroups.Keys | Sort-Object) {
        $pkgTotalLines = 0
        $pkgCoveredLines = 0

        $package = $xml.CreateElement("package")
        $classes = $xml.CreateElement("classes")

        foreach ($filename in $packageGroups[$pkgName] | Sort-Object) {
            $cls = $classData[$filename]

            $clsTotalLines = $cls.Lines.Count
            $clsCoveredLines = @($cls.Lines.Values | Where-Object { $_.Hits -gt 0 }).Count
            $clsLineRate = if ($clsTotalLines -gt 0) { [math]::Round($clsCoveredLines / $clsTotalLines, 4) } else { 0 }

            $classElement = $xml.CreateElement("class")
            $classElement.SetAttribute("name", $cls.Name)
            $classElement.SetAttribute("filename", $filename)
            $classElement.SetAttribute("line-rate", $clsLineRate.ToString())
            $classElement.SetAttribute("branch-rate", "0")
            $classElement.SetAttribute("complexity", "0")

            # Methods (omitted in merged output — per-job detail is sufficient)
            $methods = $xml.CreateElement("methods")
            $classElement.AppendChild($methods) | Out-Null

            # Lines
            $linesElement = $xml.CreateElement("lines")
            foreach ($lineNum in $cls.Lines.Keys | Sort-Object { [int]$_ }) {
                $lineData = $cls.Lines[$lineNum]
                $lineElement = $xml.CreateElement("line")
                $lineElement.SetAttribute("number", $lineNum.ToString())
                $lineElement.SetAttribute("hits", $lineData.Hits.ToString())
                $branchValue = if ($lineData.Branch) { $lineData.Branch } else { "false" }
                $lineElement.SetAttribute("branch", $branchValue)
                $linesElement.AppendChild($lineElement) | Out-Null
            }
            $classElement.AppendChild($linesElement) | Out-Null
            $classes.AppendChild($classElement) | Out-Null

            $pkgTotalLines += $clsTotalLines
            $pkgCoveredLines += $clsCoveredLines
        }

        $pkgLineRate = if ($pkgTotalLines -gt 0) { [math]::Round($pkgCoveredLines / $pkgTotalLines, 4) } else { 0 }
        $package.SetAttribute("name", $pkgName)
        $package.SetAttribute("line-rate", $pkgLineRate.ToString())
        $package.SetAttribute("branch-rate", "0")
        $package.SetAttribute("complexity", "0")
        $package.AppendChild($classes) | Out-Null
        $packagesElement.AppendChild($package) | Out-Null
    }

    # Save
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $xml.Save($OutputPath)

    $coveragePercent = if ($totalLines -gt 0) {
        [math]::Round(($coveredLines / $totalLines) * 100, 2)
    } else { 0 }

    Write-Host "`n=== Merged Coverage Summary ==="
    Write-Host "  Input files:   $($CoberturaFiles.Count)"
    Write-Host "  Classes:       $($classData.Count)"
    Write-Host "  Total lines:   $totalLines"
    Write-Host "  Covered lines: $coveredLines"
    Write-Host "  Coverage:      $coveragePercent%"
    Write-Host "================================`n"

    return [PSCustomObject]@{
        TotalLines      = $totalLines
        CoveredLines    = $coveredLines
        CoveragePercent = $coveragePercent
        LineRate        = $lineRate
        ClassCount      = $classData.Count
        PackageCount    = $packageGroups.Count
        InputFileCount  = $CoberturaFiles.Count
    }
}

<#
.SYNOPSIS
    Merges stats.json files from multiple coverage runs
.PARAMETER StatsFiles
    Array of paths to cobertura.stats.json files
.OUTPUTS
    Merged stats object with combined AppSourcePaths and excluded object data
#>
function Merge-CoverageStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$StatsFiles
    )

    $allAppSourcePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $totalExcludedObjects = 0
    $totalExcludedLinesExecuted = 0
    $totalExcludedTotalHits = 0

    foreach ($file in $StatsFiles) {
        if (-not (Test-Path $file)) { continue }
        try {
            $stats = Get-Content -Path $file -Encoding UTF8 | ConvertFrom-Json

            # Collect unique app source paths
            if ($stats | Get-Member -Name 'AppSourcePaths' -MemberType NoteProperty) {
                foreach ($path in $stats.AppSourcePaths) {
                    $allAppSourcePaths.Add($path) | Out-Null
                }
            }

            # Sum excluded object stats
            if ($stats | Get-Member -Name 'ExcludedObjectCount' -MemberType NoteProperty) {
                $totalExcludedObjects += $stats.ExcludedObjectCount
            }
            if ($stats | Get-Member -Name 'ExcludedLinesExecuted' -MemberType NoteProperty) {
                $totalExcludedLinesExecuted += $stats.ExcludedLinesExecuted
            }
            if ($stats | Get-Member -Name 'ExcludedTotalHits' -MemberType NoteProperty) {
                $totalExcludedTotalHits += $stats.ExcludedTotalHits
            }
        } catch {
            Write-Warning "Could not parse stats file $file`: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        AppSourcePaths        = @($allAppSourcePaths)
        ExcludedObjectCount   = $totalExcludedObjects
        ExcludedLinesExecuted = $totalExcludedLinesExecuted
        ExcludedTotalHits     = $totalExcludedTotalHits
    }
}

Export-ModuleMember -Function @(
    'Merge-CoberturaFiles',
    'Merge-CoverageStats'
)
