[CmdletBinding()]
param(
    [Parameter(Position = 0, mandatory = $true)] [string] $CompanyId,
    [Parameter(Position = 1, mandatory = $true)] [string] $EnvironmentName,
    [Parameter(Position = 2, mandatory = $true)] [string] $SolutionFolder
)

function Update-PowerAppSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SolutionFolder,
        
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName,
        
        [Parameter(Mandatory = $true)]
        [string]$CompanyId
    )

    # There are multiple files that contain the BC connection info for PowerApps with different structures
    # So instead of parsing all of them, we simple find the current connection strings and run a replace operation.
    # Note: The connection string has a format of: "EnvironmentName,CompanyId" where companyId is a guid. So the 
    #       replace operation should be safe to run a all json and XML files.
    Write-Host "Updating PowerApp settings"        
    $currentPowerAppSettings = Get-CurrentPowerAppSettings -solutionFolder $SolutionFolder
    if ($currentPowerAppSettings.Count -eq 0) {
        Write-Warning "Could not find PowerApps connections file"
    }

    Write-Host "Number of Business Central Power App connections found: "$currentPowerAppSettings.Count
    $newSettings = "$EnvironmentName,$CompanyId"    
    foreach ($currentSetting in $currentPowerAppSettings) {
        if ($currentSetting -eq $newSettings) {
            Write-Host "No changes needed for: "$currentSetting
            continue
        }
        write-host "Updating PowerApp settings from: $currentSetting to: $newSettings"        
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
                Write-Host "Updated: $file.FullName"
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
        $jsonFile = Get-Content  $connectionsFilePath | ConvertFrom-Json
    
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
                    continue;
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
        [string]$SolutionFolder,        
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName,        
        [Parameter(Mandatory = $true)]
        [string]$CompanyId
    )

    Write-Host "Updating Flow settings"
    $flowFilePaths = Get-ChildItem -Path "$SolutionFolder/workflows" -Recurse -Filter *.json | Select-Object -ExpandProperty FullName
        
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

    write-host "Checking flow: $FilePath"
    
    $shouldUpdate = $false

    # Update all flow triggers
    $triggersObject = $jsonObject.properties.definition.triggers
    $triggers = $triggersObject | Get-Member -MemberType Properties
    foreach ($trigger in $triggers) {
        $parametersObject = $triggersObject.($trigger.Name).inputs.parameters        
        
        if (-not $parametersObject) {
            continue
        }
        if(Update-ParameterObject -parametersObject $parametersObject -CompanyId $CompanyId -EnvironmentName $EnvironmentName){
            $shouldUpdate = $true
        }
    }
    
    # Update all flow actions
    $actionsObject = $jsonObject.properties.definition.actions
    $actions = $actionsObject | Get-Member -MemberType Properties
    foreach ($action in $actions) {
        $parametersObject = $actionsObject.($action.Name).inputs.parameters
        
        if (-not $parametersObject) {
            continue
        }      
        if(Update-ParameterObject -parametersObject $parametersObject -CompanyId $CompanyId -EnvironmentName $EnvironmentName){
            $shouldUpdate = $true
        }
    }
    if ($shouldUpdate) {
        Write-Host "Updating: $FilePath"
        # Save the updated JSON back to the file
        $jsonObject | ConvertTo-Json -Depth 100 | Set-Content  $FilePath
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
    
    write-host "Checking parameters object: "$parametersObject
    write-host "BcEnvironment: $oldBcEnvironment"
    write-host "Company: $oldCompany"

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
    
    write-host "New parameters object: "$parametersObject

    return $true
}

Write-Host "Updating the Power Platform solution Business Central connection settings"
Write-Host "New connections settings: $EnvironmentName, $CompanyId"
Update-PowerAppSettings -SolutionFolder $SolutionFolder -EnvironmentName $EnvironmentName -CompanyId $CompanyId
Update-FlowSettings -SolutionFolder $SolutionFolder -EnvironmentName $EnvironmentName -CompanyId $CompanyId
