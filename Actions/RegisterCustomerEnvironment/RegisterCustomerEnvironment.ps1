Param(
    [string] $actor,
    [string] $token,
    [string] $workflowToken,
    [string] $name,
    [string] $tenantId,
    [string] $environmentName,
    [string] $aadAppClientId,
    [string] $aadAppClientSecretName,
    [bool] $productionEnvironment,
    [bool] $continuousDeployment,
    [bool] $manualDeployment,
    [bool] $directCommit
)

function CreateReleaseWorkflow {
    Param(
        [string] $filename,
        [string] $description,
        [string] $name,
        [string] $tenantId,
        [string] $environmentName
    )

    $template = Get-Content -raw -Path (Join-Path ([System.IO.Path]::GetDirectoryName($filename)) "ReleaseWorkflowTemplate.yaml.txt")
    $template.Replace('{0}',$description).Replace('{1}',$tenantId).Replace('{2}',$environmentName).Replace('{3}',$name) | Set-Content $filename
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    if ($manualDeployment) {
        if ($workflowToken -eq "") {
            OutputError "In order to create manual deployment workflows, you need to add a secret called GHTOKENWORKFLOW containing a personal access token with permissions to modify Workflows. This is done by opening https://github.com/settings/tokens, Generate a new token and check the workflow scope."
            exit
        }
        $token = $workflowToken
    }
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch

    try {
        if (Test-Path $customerEnvironmentsFile) {
            Write-Host "Reading $customerEnvironmentsFile"
            $customerEnvironments = @(Get-Content $customerEnvironmentsFile | ConvertFrom-Json)
        }
        else {
            $customerEnvironments = @()
        }

        $commitMessage = "Add Customer Environment $name/$environmentName in tenant $tenantId"
        $releaseWorkflowFileName = ".github\workflows\ReleaseTo$name-$environmentName-$tenantId.yaml"
        $releaseWorkflowDescription = "Release to $name/$environmentName in tenant $tenantId"

        $existingEnv = $customerEnvironments | Where-Object { $_.name -eq $name -and $_.environmentName -eq $environmentName -and $_.tenantId -eq $tenantId }
        if ($existingEnv) {
            if ($aadAppClientId -eq "" -and $aadAppClientSecretName -eq "") {
                OutputWarning -message "Customer environment $name/$environmentName in tenant $tenantId will be removed."
                $customerEnvironments = @($customerEnvironments | Where-Object { $_.name -ne $name -or $_.environmentName -ne $environmentName -or $_.tenantId -ne $tenantId })
                $commitMessage = "Remove Customer Environment $name/$environmentName in tenant $tenantId"
                if (Test-Path -path $releaseWorkflowFileName -PathType Leaf) {
                    Remove-Item $releaseWorkflowFileName -Force
                }
            }
            else {
                OutputWarning -message "Customer environment $name/$environmentName in tenant $tenantId will be updated."
                $commitMessage = "Update Customer Environment $name/$environmentName in tenant $tenantId"
                $existingEnv.aadAppClientId = $aadAppClientId
                $existingEnv.aadAppClientSecretName = $aadAppClientSecretName
                $existingEnv.productionEnvironment = $productionEnvironment
                $existingEnv.continuousDeployment = $continuousDeployment
                $existingEnv.manualDeployment = $manualDeployment
                if ($manualDeployment) {
                    CreateReleaseWorkflow -filename $releaseWorkflowFileName -description $releaseWorkflowDescription -name $name -tenantId $tenantId -environmentName $environmentName
                }
            }
        }
        else {
            if ($aadAppClientId -eq "" -and $aadAppClientSecretName -eq "") {
                OutputError -message "No aadAppClientId and Secret was specified. Customer Environment will not be created"
                exit
            }
            
            $customerEnvironments += @([ordered]@{
                "name" = $name
                "tenantId" = $tenantId
                "environmentName" = $environmentName
                "aadAppClientId" = $aadAppClientId
                "aadAppClientSecretName" = $aadAppClientSecretName
                "productionEnvironment" = $productionEnvironment
                "continuousDeployment" = $continuousDeployment
                "manualDeployment" = $manualDeployment
            })
            if ($manualDeployment) {
                CreateReleaseWorkflow -filename $releaseWorkflowFileName -description $releaseWorkflowDescription -name $name -tenantId $tenantId -environmentName $environmentName
            }
        }

        $customerEnvironments | ConvertTo-Json -Depth 99 | Set-Content $customerEnvironmentsFile
    }
    catch {
        OutputError "CustomerEnvironments file $customerEnvironmentsFile, is wrongly formatted. Error is $($_.Exception.Message)."
        exit
    }

    CommitFromNewFolder -serverUrl $serverUrl -commitMessage $commitMessage -branch $branch
}
catch {
    OutputError -message "Couldn't add Customer Environment. Error was $($_.Exception.Message)"
}
