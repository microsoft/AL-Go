<#
.SYNOPSIS
    Formats code coverage data as Cobertura XML
.DESCRIPTION
    Converts BC code coverage data into standard Cobertura XML format
    for use with coverage visualization tools and GitHub Actions.
#>

<#
.SYNOPSIS
    Creates a Cobertura XML document from coverage data
.PARAMETER CoverageData
    Processed coverage data with object and line information
.PARAMETER SourcePath
    Base path for source files (used in sources element)
.PARAMETER AppInfo
    Optional app metadata (Name, Publisher, Version)
.OUTPUTS
    XmlDocument containing Cobertura-formatted coverage
#>
function New-CoberturaDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CoverageData,
        
        [Parameter(Mandatory = $false)]
        [string]$SourcePath = "",
        
        [Parameter(Mandatory = $false)]
        $AppInfo = $null
    )
    
    # Calculate overall statistics
    # XMLport 130470 only exports covered lines, so we need source info for total executable lines
    $totalExecutableLines = 0
    $coveredLines = 0
    
    foreach ($obj in $CoverageData.Values) {
        # Prefer source-based count for total lines (accurate for XMLport 130470)
        # Fall back to coverage data line count if no source info available
        $objTotalLines = 0
        if ($obj.SourceInfo -and $obj.SourceInfo.ExecutableLines) {
            $objTotalLines = $obj.SourceInfo.ExecutableLines
        } elseif ($obj.Lines.Count -gt 0) {
            $objTotalLines = $obj.Lines.Count
        }
        
        $totalExecutableLines += $objTotalLines
        
        # Count covered lines from coverage data
        foreach ($line in $obj.Lines) {
            if ($line.IsCovered) { $coveredLines++ }
        }
    }
    
    $lineRate = if ($totalExecutableLines -gt 0) { [math]::Round($coveredLines / $totalExecutableLines, 4) } else { 0 }
    $branchRate = 0  # BC coverage doesn't provide branch information
    
    # Create XML document
    $xml = New-Object System.Xml.XmlDocument
    
    # XML declaration
    $declaration = $xml.CreateXmlDeclaration("1.0", "UTF-8", $null)
    $xml.AppendChild($declaration) | Out-Null
    
    # DOCTYPE for Cobertura
    # Note: Omitting DOCTYPE as many tools don't require it and it can cause issues
    
    # Root coverage element
    $coverage = $xml.CreateElement("coverage")
    $coverage.SetAttribute("line-rate", $lineRate.ToString())
    $coverage.SetAttribute("branch-rate", $branchRate.ToString())
    $coverage.SetAttribute("lines-covered", $coveredLines.ToString())
    $coverage.SetAttribute("lines-valid", $totalExecutableLines.ToString())
    $coverage.SetAttribute("branches-covered", "0")
    $coverage.SetAttribute("branches-valid", "0")
    $coverage.SetAttribute("complexity", "0")
    $coverage.SetAttribute("version", "1.0")
    $coverage.SetAttribute("timestamp", [DateTimeOffset]::Now.ToUnixTimeSeconds().ToString())
    $xml.AppendChild($coverage) | Out-Null
    
    # Sources element
    $sources = $xml.CreateElement("sources")
    $source = $xml.CreateElement("source")
    $source.InnerText = if ($SourcePath) { $SourcePath } else { "." }
    $sources.AppendChild($source) | Out-Null
    $coverage.AppendChild($sources) | Out-Null
    
    # Packages element
    $packages = $xml.CreateElement("packages")
    $coverage.AppendChild($packages) | Out-Null
    
    # Create a package for the app
    $packageName = if ($AppInfo -and $AppInfo.Name) { $AppInfo.Name } else { "BCApp" }
    $package = $xml.CreateElement("package")
    $package.SetAttribute("name", $packageName)
    $package.SetAttribute("line-rate", $lineRate.ToString())
    $package.SetAttribute("branch-rate", "0")
    $package.SetAttribute("complexity", "0")
    $packages.AppendChild($package) | Out-Null
    
    # Classes element within package
    $classes = $xml.CreateElement("classes")
    $package.AppendChild($classes) | Out-Null
    
    # Add each object as a class
    foreach ($key in $CoverageData.Keys | Sort-Object) {
        $obj = $CoverageData[$key]
        $classElement = New-CoberturaClass -Xml $xml -ObjectData $obj
        $classes.AppendChild($classElement) | Out-Null
    }
    
    return $xml
}

<#
.SYNOPSIS
    Creates a Cobertura class element for a BC object
.PARAMETER Xml
    The parent XmlDocument
.PARAMETER ObjectData
    Object data with type, id, lines, and optional source info
.OUTPUTS
    XmlElement for the class
#>
function New-CoberturaClass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$Xml,
        
        [Parameter(Mandatory = $true)]
        $ObjectData
    )
    
    # Calculate class statistics
    # Prefer source-based count for total lines (accurate for XMLport 130470)
    $totalExecutableLines = 0
    if ($ObjectData.SourceInfo -and $ObjectData.SourceInfo.ExecutableLines) {
        $totalExecutableLines = $ObjectData.SourceInfo.ExecutableLines
    } elseif ($ObjectData.Lines.Count -gt 0) {
        $totalExecutableLines = $ObjectData.Lines.Count
    }
    $coveredLines = @($ObjectData.Lines | Where-Object { $_.IsCovered }).Count
    $lineRate = if ($totalExecutableLines -gt 0) { [math]::Round($coveredLines / $totalExecutableLines, 4) } else { 0 }
    
    # Create class element
    $class = $Xml.CreateElement("class")
    
    # Class name: ObjectType.ObjectId (e.g., "Codeunit.50100")
    $className = "$($ObjectData.ObjectType).$($ObjectData.ObjectId)"
    $class.SetAttribute("name", $className)
    
    # Filename - use source file path if available, otherwise construct a logical name
    $filename = if ($ObjectData.SourceInfo -and $ObjectData.SourceInfo.RelativePath) {
        $ObjectData.SourceInfo.RelativePath
    } else {
        "$($ObjectData.ObjectType)/$($ObjectData.ObjectId).al"
    }
    $class.SetAttribute("filename", $filename.Replace('\', '/'))
    
    $class.SetAttribute("line-rate", $lineRate.ToString())
    $class.SetAttribute("branch-rate", "0")
    $class.SetAttribute("complexity", "0")
    
    # Methods element
    $methods = $Xml.CreateElement("methods")
    $class.AppendChild($methods) | Out-Null
    
    # Group lines by procedure if source info available and there are lines to process
    if ($ObjectData.SourceInfo -and $ObjectData.SourceInfo.Procedures -and $ObjectData.Lines -and $ObjectData.Lines.Count -gt 0) {
        $procedureCoverage = Get-ProcedureCoverage -Lines $ObjectData.Lines -Procedures $ObjectData.SourceInfo.Procedures
        
        foreach ($proc in $procedureCoverage) {
            $method = New-CoberturaMethod -Xml $Xml -ProcedureData $proc
            $methods.AppendChild($method) | Out-Null
        }
    }
    
    # Lines element (all executable lines for the class)
    $linesElement = $Xml.CreateElement("lines")
    $class.AppendChild($linesElement) | Out-Null
    
    # Build a set of covered line numbers for quick lookup
    $coveredLineNumbers = @{}
    foreach ($line in $ObjectData.Lines) {
        $coveredLineNumbers[$line.LineNo] = $line.Hits
    }
    
    # If we have source info with executable line numbers, include all of them
    if ($ObjectData.SourceInfo -and $ObjectData.SourceInfo.ExecutableLineNumbers) {
        foreach ($lineNo in $ObjectData.SourceInfo.ExecutableLineNumbers | Sort-Object) {
            $lineElement = $Xml.CreateElement("line")
            $lineElement.SetAttribute("number", $lineNo.ToString())
            $hits = if ($coveredLineNumbers.ContainsKey($lineNo)) { $coveredLineNumbers[$lineNo] } else { 0 }
            $lineElement.SetAttribute("hits", $hits.ToString())
            $lineElement.SetAttribute("branch", "false")
            $linesElement.AppendChild($lineElement) | Out-Null
        }
    } else {
        # Fallback: only output covered lines (BC data only)
        foreach ($line in $ObjectData.Lines | Sort-Object -Property LineNo) {
            $lineElement = $Xml.CreateElement("line")
            $lineElement.SetAttribute("number", $line.LineNo.ToString())
            $lineElement.SetAttribute("hits", $line.Hits.ToString())
            $lineElement.SetAttribute("branch", "false")
            $linesElement.AppendChild($lineElement) | Out-Null
        }
    }
    
    return $class
}

<#
.SYNOPSIS
    Creates a Cobertura method element
.PARAMETER Xml
    The parent XmlDocument
.PARAMETER ProcedureData
    Procedure data with name and line coverage
.OUTPUTS
    XmlElement for the method
#>
function New-CoberturaMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$Xml,
        
        [Parameter(Mandatory = $true)]
        $ProcedureData
    )
    
    $method = $Xml.CreateElement("method")
    $method.SetAttribute("name", $ProcedureData.Name)
    $method.SetAttribute("signature", "()")  # AL doesn't have traditional signatures
    
    $totalLines = $ProcedureData.Lines.Count
    $coveredLines = ($ProcedureData.Lines | Where-Object { $_.IsCovered }).Count
    $lineRate = if ($totalLines -gt 0) { [math]::Round($coveredLines / $totalLines, 4) } else { 0 }
    
    $method.SetAttribute("line-rate", $lineRate.ToString())
    $method.SetAttribute("branch-rate", "0")
    $method.SetAttribute("complexity", "0")
    
    # Lines within method
    $lines = $Xml.CreateElement("lines")
    $method.AppendChild($lines) | Out-Null
    
    foreach ($line in $ProcedureData.Lines | Sort-Object -Property LineNo) {
        $lineElement = $Xml.CreateElement("line")
        $lineElement.SetAttribute("number", $line.LineNo.ToString())
        $lineElement.SetAttribute("hits", $line.Hits.ToString())
        $lineElement.SetAttribute("branch", "false")
        $lines.AppendChild($lineElement) | Out-Null
    }
    
    return $method
}

<#
.SYNOPSIS
    Groups coverage lines by procedure
.PARAMETER Lines
    Array of coverage line entries
.PARAMETER Procedures
    Array of procedure definitions with StartLine/EndLine
.OUTPUTS
    Array of procedure coverage objects
#>
function Get-ProcedureCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [array]$Lines = @(),
        
        [Parameter(Mandatory = $true)]
        [array]$Procedures
    )
    
    $result = @()
    
    # If no lines, return empty result
    if (-not $Lines -or $Lines.Count -eq 0) {
        return $result
    }
    
    foreach ($proc in $Procedures) {
        $procLines = $Lines | Where-Object { 
            $_.LineNo -ge $proc.StartLine -and $_.LineNo -le $proc.EndLine 
        }
        
        if ($procLines.Count -gt 0) {
            $result += [PSCustomObject]@{
                Name  = $proc.Name
                Type  = $proc.Type
                Lines = $procLines
            }
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Saves a Cobertura XML document to file
.PARAMETER XmlDocument
    The Cobertura XmlDocument
.PARAMETER OutputPath
    Path to save the XML file
#>
function Save-CoberturaFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$XmlDocument,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    # Ensure directory exists
    $directory = Split-Path -Path $OutputPath -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    
    # Configure XML writer settings for proper formatting
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "  "
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)  # UTF-8 without BOM
    
    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    try {
        $XmlDocument.Save($writer)
    }
    finally {
        $writer.Close()
    }
    
    Write-Host "Saved Cobertura coverage report to: $OutputPath"
}

<#
.SYNOPSIS
    Creates a minimal Cobertura document for summary display
.PARAMETER TotalLines
    Total number of lines
.PARAMETER CoveredLines
    Number of covered lines
.PARAMETER PackageName
    Name for the package
.OUTPUTS
    XmlDocument with summary coverage
#>
function New-CoberturaSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$TotalLines,
        
        [Parameter(Mandatory = $true)]
        [int]$CoveredLines,
        
        [Parameter(Mandatory = $false)]
        [string]$PackageName = "BCApp"
    )
    
    $lineRate = if ($TotalLines -gt 0) { [math]::Round($CoveredLines / $TotalLines, 4) } else { 0 }
    
    $xml = New-Object System.Xml.XmlDocument
    $declaration = $xml.CreateXmlDeclaration("1.0", "UTF-8", $null)
    $xml.AppendChild($declaration) | Out-Null
    
    $coverage = $xml.CreateElement("coverage")
    $coverage.SetAttribute("line-rate", $lineRate.ToString())
    $coverage.SetAttribute("branch-rate", "0")
    $coverage.SetAttribute("lines-covered", $CoveredLines.ToString())
    $coverage.SetAttribute("lines-valid", $TotalLines.ToString())
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
    
    $packages = $xml.CreateElement("packages")
    $package = $xml.CreateElement("package")
    $package.SetAttribute("name", $PackageName)
    $package.SetAttribute("line-rate", $lineRate.ToString())
    $package.SetAttribute("branch-rate", "0")
    $package.SetAttribute("complexity", "0")
    $packages.AppendChild($package) | Out-Null
    $coverage.AppendChild($packages) | Out-Null
    
    $classes = $xml.CreateElement("classes")
    $package.AppendChild($classes) | Out-Null
    
    return $xml
}

Export-ModuleMember -Function @(
    'New-CoberturaDocument',
    'New-CoberturaClass',
    'New-CoberturaMethod',
    'Get-ProcedureCoverage',
    'Save-CoberturaFile',
    'New-CoberturaSummary'
)
