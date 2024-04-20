[CmdletBinding()]
param(
    [Parameter(Position = 0, mandatory = $true)] [string] $solutionFolder,
    [Parameter(Position = 1, mandatory = $false)] [string] $CompanyId,
    [Parameter(Position = 2, mandatory = $false)] [string] $EnvironmentName,
    [Parameter(Position = 3, mandatory = $false)] [string] $appBuild,
    [Parameter(Position = 4, mandatory = $false)] [string] $appRevision,
    [Parameter(Position = 5, mandatory = $false)] [string] $managed
)
$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function Update-PowerAppSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SolutionFolder,
        [Parameter(Mandatory = $true)]
        [string] $EnvironmentName,
        [Parameter(Mandatory = $true)]
        [string] $CompanyId
    )

    # There are multiple files that contain the BC connection info for PowerApps with different structures
    # So instead of parsing all of them, we simple find the current connection strings and run a replace operation.
    # Note: The connection string has a format of: "EnvironmentName,CompanyId" where companyId is a guid. So the
    #       replace operation should be safe to run a all json and XML files.
    Write-Host "Updating PowerApp settings"
    $currentPowerAppSettings = Get-CurrentPowerAppSettings -solutionFolder $SolutionFolder
    if ($null -eq $currentPowerAppSettings) {
        Write-Host "::Notice::No Power Apps found"
        return
    }

    Write-Host "Number of Business Central Power App connections found: "$currentPowerAppSettings.Count
    $newSettings = "$EnvironmentName,$CompanyId"
    foreach ($currentSetting in $currentPowerAppSettings) {
        if ($currentSetting -eq $newSettings) {
            Write-Host "No changes needed for: "$currentSetting
            continue
        }
        Update-PowerAppFiles -oldSetting $currentSetting -newSetting $newSettings -solutionFolder $SolutionFolder
    }
}

function Update-PowerAppFiles {
    param(
        [Parameter(Position = 0, mandatory = $true)] [string] $solutionFolder,
        [Parameter(Position = 0, mandatory = $true)] [string] $oldSetting,
        [Parameter(Position = 0, mandatory = $true)] [string] $newSetting
    )

    $powerAppFiles = Get-ChildItem -Recurse -File "$solutionFolder/CanvasApps"
    foreach ($file in $powerAppFiles) {
        # only check json and xml files
        if (($file.Extension -eq ".json") -or ($file.Extension -eq ".xml")) {
            $fileContent = Get-Content  $file.FullName
            if (Select-String -Pattern $oldSetting -InputObject $fileContent) {
                $fileContent = $fileContent -creplace $oldSetting, $newSetting
                Set-Content -Path $file.FullName -Value $fileContent
                Write-Host "Updated: $($file.FullName)"
            }
        }
    }
}

function Get-CurrentPowerAppSettings {
    param (
        [Parameter(Position = 0, mandatory = $true)] [string] $solutionFolder
    )

    if (-not (Test-Path -Path "$solutionFolder/CanvasApps")) {
        # No Canvas apps present in the solution
        return @()
    }

    $currentSettingsList = @()
    $connectionsFilePaths = Get-ChildItem -Path "$solutionFolder/CanvasApps" -Recurse -File -Include "Connections.json" | Select-Object -ExpandProperty FullName
    foreach ($connectionsFilePath in $connectionsFilePaths) {
        $jsonFile = Get-Content $connectionsFilePath | ConvertFrom-Json

        # We don't know the name of the connector node, so we need to loop through all of them
        $ConnectorNodeNames = ($jsonFile | Get-Member -MemberType NoteProperty).Name

        foreach ($connectorNodeName in $ConnectorNodeNames) {
            $connectorNode = $jsonFile.$connectorNodeName
            # Find the Business Central connection node
            if ($connectorNode.connectionRef.displayName -eq "Dynamics 365 Business Central") {
                $currentEnvironmentAndCompany = ($connectorNode.datasets | Get-Member -MemberType NoteProperty).Name

                if ($null -eq $currentEnvironmentAndCompany) {
                    # Connections sections for Power Automate flow does not have a dataset node
                    # Note: Flows are handled in a different function
                    continue
                }

                if (!$currentsettingsList.Contains($currentEnvironmentAndCompany)) {
                    $currentSettingsList += $currentEnvironmentAndCompany

                    # The Business Central environment can be be inconsistant - Either starting with a capital letter or all caps.
                    # Add both variants to ensure we find all connections
                    $currentSettingsParts = @($currentEnvironmentAndCompany.Split(","))
                    $currentSettingsList += "$($currentSettingsParts[0].ToUpperInvariant()),$($currentSettingsParts[1])"
                }
            }
        }
    }
    return $currentSettingsList
}

function Update-FlowSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SolutionFolder,
        [Parameter(Mandatory = $true)]
        [string] $EnvironmentName,
        [Parameter(Mandatory = $true)]
        [string] $CompanyId
    )

    Write-Host "Updating Flow settings"
    $flowFilePaths = Get-ChildItem -Path "$SolutionFolder/workflows" -Recurse -Filter *.json | Select-Object -ExpandProperty FullName

    if ($null -eq $flowFilePaths) {
        Write-Host "::Notice::No Power Automate flows found"
        return
    }
        
    foreach ($flowFilePath in $flowFilePaths) {
        Update-FlowFile -FilePath $flowFilePath -CompanyId $CompanyId -EnvironmentName $EnvironmentName
    }
}

function Update-FlowFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$CompanyId,
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName
    )
    # Read the JSON file
    $jsonObject = Get-Content $FilePath  | ConvertFrom-Json
    $shouldUpdate = $false

    # Update all flow triggers
    $triggersObject = $jsonObject.properties.definition.triggers
    $triggers = $triggersObject | Get-Member -MemberType Properties
    foreach ($trigger in $triggers) {
        $triggerInputs = $triggersObject.($trigger.Name).inputs

        if ($triggerInputs | Get-Member -MemberType Properties -name 'parameters') {
            # Business Central triggers have connection information in the input parameters
            if (Update-ParameterObject -parametersObject $triggerInputs.parameters -CompanyId $CompanyId -EnvironmentName $EnvironmentName) {
                $shouldUpdate = $true
            }
        }
    }

    # Update all flow actions
    $actionsObject = $jsonObject.properties.definition.actions
    $actions = $actionsObject | Get-Member -MemberType Properties
    foreach ($action in $actions) {
        $actionInput = $actionsObject.($action.Name).inputs
        if ($actionInput | Get-Member -MemberType Properties -name 'parameters') {
            # Business Central actions have connection information in the input parameters
            if (Update-ParameterObject -parametersObject $actionInput.parameters -CompanyId $CompanyId -EnvironmentName $EnvironmentName) {
                $shouldUpdate = $true
            }
        }
    }
    if ($shouldUpdate) {
        # Save the updated JSON back to the file
        $jsonObject | ConvertTo-Json -Depth 100 | Set-Content  $FilePath
        Write-Host "Updated: $FilePath"
    }
    else {
        Write-Host "No update needed for: $FilePath"
    }
}

function Update-ParameterObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Object]$parametersObject,
        [Parameter(Mandatory = $true)]
        [string]$CompanyId,
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName
    )
    # Check if paramers are for Business Central
    if ((-not $parametersObject.company) -or (-not $parametersObject.bcEnvironment)) {
        return $false
    }

    $oldCompany = $parametersObject.company
    $oldBcEnvironment = $parametersObject.bcenvironment

    # Check if parameters are already set to the correct values
    if (($oldCompany -eq $CompanyId) -and ($oldBcEnvironment -eq $EnvironmentName)) {
        return $false
    }

    $enviromentVariablePlaceHolder = "@parameters("

    # Check if parameters are set using a different approach (e.g. environment variables or passed in parameters)
    if ($oldCompany.contains($enviromentVariablePlaceHolder) -or $oldBcEnvironment.contains($enviromentVariablePlaceHolder)) {
        return $false
    }

    $parametersObject.company = $CompanyId
    $parametersObject.bcEnvironment = $EnvironmentName

    return $true
}

function Update-SolutionVersionNode {
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

}

function Update-SolutionManagedNode {
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

if ($appBuild -and $appRevision) {
    Write-Host "Updating Power Platform solution file ($solutionFolder)"
    $solutionDefinitionFile = Join-Path $solutionFolder 'other\Solution.xml'
    $xmlFile = [xml](Get-Content -Encoding UTF8 -Path $solutionDefinitionFile)
    Update-SolutionVersionNode -appBuild $appBuild -appRevision $appRevision -xmlFile $xmlFile
    $xmlFile.Save($solutionDefinitionFile)
}
else {
    Write-Host "Skip solution version update since appBuild and appRevision are not set"  
}

if ($EnvironmentName -and $CompanyId) {   
    Write-Host "Updating the Power Platform solution Business Central connection settings"
    Write-Host "New connections settings: $EnvironmentName, $CompanyId"
    Update-PowerAppSettings -SolutionFolder $SolutionFolder -EnvironmentName $EnvironmentName -CompanyId $CompanyId
    Update-FlowSettings -SolutionFolder $SolutionFolder -EnvironmentName $EnvironmentName -CompanyId $CompanyId
}
else {
    Write-Host "Skip Business Central connection settings update since EnvironmentName and CompanyId are not set"
}