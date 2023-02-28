[CmdletBinding()]
param(
    [Parameter(Position = 0, mandatory = $true)]
    [string] $solutionFolder,
    [Parameter(Position = 1, mandatory = $true)]
    [string] $appBuild,
    [Parameter(Position = 2, mandatory = $true)]
    [string] $appRevision,
    [Parameter(Position = 3, mandatory = $false)]
    [string] $managed
)

function Update-VersionNode {
    param(
        [Parameter(Position = 0, mandatory = $true)]
        [string] $appBuild,
        [Parameter(Position = 1, mandatory = $true)]
        [string] $appRevision,
        [Parameter(Position = 2, mandatory = $true)]
        [xml] $xmlFile
    )

    if ($appBuild -and $appRevision) {
        $versionNode = $xmlFile.SelectSingleNode("//Version")
        $versionNodeText = $versionNode.'#text'
        
        $versionParts = $versionNodeText.Split('.')
        # Only update the last two parts of the version number - major and minor version should be set manually
        $newVersionNumber = $versionParts[0] + '.' + $versionParts[1] + '.' + $appBuild + '.' + $appRevision

        Write-Host "New version: "$newVersionNumber
        $versionNode.'#text' = $newVersionNumber
    }
    else {
        Write-Host "Skipping version update since appBuild and appRevision are not set ($appBuild, $appRevision)"
    }
}

function Update-ManagedNode {
    param(
        [Parameter(Position = 0, mandatory = $false)]
        [string] $managed,
        [Parameter(Position = 1, mandatory = $true)]
        [xml] $xmlFile
    )
    
    $managedValue = "0"
    if ($managed -eq "true") {
        $managedValue = "1"
    }

    $nodeWithName = $xmlFile.SelectSingleNode("//Managed")
    Write-Host "Updating managed flag: "$managedValue
    $nodeWithName.'#text' = $managedValue    
}

Write-Host "Updating Power Platform solution ($solutionFolder)"
$solutionDefinitionFile = $solutionFolder + "\other\solution.xml"
$xmlFile = [xml](Get-Content $solutionDefinitionFile)

Update-VersionNode -appBuild $appBuild -appRevision $appRevision -xmlFile $xmlFile
Update-ManagedNode -managed $managed -xmlFile $xmlFile
        
$xmlFile.Save($solutionDefinitionFile)
