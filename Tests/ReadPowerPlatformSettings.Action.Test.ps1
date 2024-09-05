Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Read Power Platform Settings Action Tests" {
    BeforeAll {
        $actionName = "ReadPowerPlatformSettings"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        function ConvertToDeployToSettings {
            param (
                [Parameter(Mandatory = $true)]
                [hashtable] $deployToDevProperties
            )
            return @{
                type                        = "PTE"
                powerPlatformSolutionFolder = "CoffeMR"
                DeployToDev                 = $deployToDevProperties
            } | ConvertTo-Json
        }

        function SetSecretsEnvVariable {
            param (
                [Parameter(Mandatory = $true)]
                [hashtable] $secretProperties
            )
            $testSecret = $secretProperties | ConvertTo-Json
            $env:Secrets = '{"DeployToDev-AuthContext": "' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($testSecret)) + '"}'
        }
    }

    BeforeEach {
        Write-Host "Before test"
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_ENV = [System.IO.Path]::GetTempFileName()

        Write-Host $env:GITHUB_OUTPUT
        Write-Host $env:GITHUB_ENV

        Invoke-Expression $actionScript
    }

    AfterEach {
        Write-Host "After test"
        Remove-Item -Path $env:GITHUB_OUTPUT -Force
        Remove-Item -Path $env:GITHUB_ENV -Force

        $env:Secrets = $null
    }

    It 'Sets the correct GitHub environment variables - service principle auth' {
        # Setup deploy to settings
        $deployToDevProperties = @{
            environmentName  = "sandbox"
            companyId        = "11111111-1111-1111-1111-111111111111"
            ppEnvironmentUrl = "https://TestUrL.crm.dynamics.com"
        }
        $jsonInput = ConvertToDeployToSettings -deployToDevProperties $deployToDevProperties

        # Setup secrets as GitHub environment variable
        $secretProperties = @{
            ppTenantId      = "your-tenant-id"
            ppApplicationId = "your-application-id"
            ppClientSecret  = "your-client-secret"
        }
        SetSecretsEnvVariable -secretProperties $secretProperties

        # Run the action
        ReadPowerPlatformSettings -deploymentEnvironmentsJson $jsonInput -environmentName "DeployToDev"

        # Assert the GitHub environment variables are set correctly
        $gitHubEnvPlaceholder = Get-Content -Path $env:GITHUB_OUTPUT
        $gitHubEnvPlaceholder | Should -Contain ("ppEnvironmentUrl=" + $deployToDevProperties.ppEnvironmentUrl)
        $gitHubEnvPlaceholder | Should -Contain ("companyId=" + $deployToDevProperties.companyId)
        $gitHubEnvPlaceholder | Should -Contain ("environmentName=" + $deployToDevProperties.environmentName)
        $gitHubEnvPlaceholder | Should -Contain ("ppTenantId=" + $secretProperties.ppTenantId)
        $gitHubEnvPlaceholder | Should -Contain ("ppApplicationId=" + $secretProperties.ppApplicationId)
        $gitHubEnvPlaceholder | Should -Contain ("ppClientSecret=" + $secretProperties.ppClientSecret)
    }

    It 'Sets the correct GitHub environment variables - user auth' {
        # Setup deploy to settings
        $deployToDevProperties = @{
            environmentName  = "sandbox"
            companyId        = "11111111-1111-1111-1111-111111111111"
            ppEnvironmentUrl = "https://TestUrL.crm.dynamics.com"
        }
        $jsonInput = ConvertToDeployToSettings -deployToDevProperties $deployToDevProperties

        # Setup secrets as GitHub environment variable
        $secretProperties = @{
            ppUserName      = "your-username"
            ppPassword      = "your-password"
        }
        SetSecretsEnvVariable -secretProperties $secretProperties

        # Run the action
        ReadPowerPlatformSettings -deploymentEnvironmentsJson $jsonInput -environmentName "DeployToDev"

        # Assert the GitHub environment variables are set correctly
        $gitHubEnvPlaceholder = Get-Content -Path $env:GITHUB_OUTPUT
        $gitHubEnvPlaceholder | Should -Contain ("ppEnvironmentUrl=" + $deployToDevProperties.ppEnvironmentUrl)
        $gitHubEnvPlaceholder | Should -Contain ("companyId=" + $deployToDevProperties.companyId)
        $gitHubEnvPlaceholder | Should -Contain ("environmentName=" + $deployToDevProperties.environmentName)
        $gitHubEnvPlaceholder | Should -Contain ("ppUserName=" + $secretProperties.ppUserName)
        $gitHubEnvPlaceholder | Should -Contain ("ppPassword=" + $secretProperties.ppPassword)

    }

    It 'Fails if required deployment settings are missing' {
        function runMissingSettingsTest {
            param (
                [hashtable] $deployToDevProperties
            )
            # Convert hashtables to JSON strings
            $jsonInput = ConvertToDeployToSettings -deployToDevProperties $deployToDevProperties

            $errorObject = $null
            $HasThrownException = $false
            # Run the action
            try {
                ReadPowerPlatformSettings -deploymentEnvironmentsJson $jsonInput -environmentName "DeployToDev"
            }
            catch {
                $errorObject = $_
                $HasThrownException = $true
            }

            $HasThrownException | Should -Be $true
            return $errorObject.TargetObject
        }

        # Test missing ppEnvironmentUrl
        $deployToDevProperties = @{
            environmentName = "sandbox"
            companyId       = "11111111-1111-1111-1111-111111111111"
        }
        $errorMessage = runMissingSettingsTest -deployToDevProperties $deployToDevProperties
        $errorMessage | Should -Be "DeployToDev setting must contain 'ppEnvironmentUrl' property"

        # Test missing companyId
        $deployToDevProperties = @{
            environmentName  = "sandbox"
            ppEnvironmentUrl = "https://TestUrL.crm.dynamics.com"
        }
        $errorMessage = runMissingSettingsTest -deployToDevProperties $deployToDevProperties
        $errorMessage | Should -Be "DeployToDev setting must contain 'companyId' property"

        # Test missing environmentName
        $deployToDevProperties = @{
            companyId        = "11111111-1111-1111-1111-111111111111"
            ppEnvironmentUrl = "https://TestUrL.crm.dynamics.com"
        }
        $errorMessage = runMissingSettingsTest -deployToDevProperties $deployToDevProperties
        $errorMessage | Should -Be "DeployToDev setting must contain 'environmentName' property"

    }

    It 'Fails if required secret settings are missing' {
        function runMissingSecretsTest {
            # Test missing ppEnvironmentUrl
            $deployToDevProperties = @{
                environmentName  = "sandbox"
                companyId        = "11111111-1111-1111-1111-111111111111"
                ppEnvironmentUrl = "https://TestUrL.crm.dynamics.com"
            }
            # Convert hashtables to JSON strings
            $jsonInput = ConvertToDeployToSettings -deployToDevProperties $deployToDevProperties

            $errorObject = $null
            # Run the action
            try {
                ReadPowerPlatformSettings -deploymentEnvironmentsJson $jsonInput -environmentName "DeployToDev"
            }
            catch {
                $errorObject = $_
                $HasThrownException = $true
            }

            $HasThrownException | Should -Be $true
            return $errorObject.TargetObject
        }

        # Test secret missing ppTenantId
        $secretProperties = @{
            ppApplicationId = "your-application-id"
            ppClientSecret  = "your-client-secret"
        }
        SetSecretsEnvVariable -secretProperties $secretProperties
        $errorMessage = runMissingSecretsTest
        $errorMessage | Should -Be "Secret DeployToDev-AuthContext must contain either 'ppUserName' and 'ppPassword' properties or 'ppApplicationId', 'ppClientSecret' and 'ppTenantId' properties"


        # Test secret missing username
        $secretProperties = @{
            username        = "your-username"
        }
        SetSecretsEnvVariable -secretProperties $secretProperties
        $errorMessage = runMissingSecretsTest
        $errorMessage | Should -Be "Secret DeployToDev-AuthContext must contain either 'ppUserName' and 'ppPassword' properties or 'ppApplicationId', 'ppClientSecret' and 'ppTenantId' properties"

    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
            "ppEnvironmentUrl" = "Power Platform Environment URL"
            "ppUserName" = "Power Platform Username"
            "ppPassword" = "Power Platform Password"
            "ppApplicationId" = "Power Platform Application Id"
            "ppTenantId" = "Power Platform Tenant Id"
            "ppClientSecret" = "Power Platform Client Secret"
            "companyId" = "Business Central Company Id"
            "environmentName" = "Business Central Environment Name"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }
}
