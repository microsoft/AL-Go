Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force

Describe "DetermineDeploymentEnvironments Action Test" {
    BeforeAll {
        $actionName = "DetermineDeploymentEnvironments"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        function PassGeneratedOutput() {
            Get-Content $env:GITHUB_OUTPUT -Encoding UTF8 | ForEach-Object {
                Set-Variable -Scope Script -Name $_.Split('=')[0] -Value $_.SubString($_.IndexOf('=')+1)
            }
        }
    }

    BeforeEach {
        $env:GITHUB_REF_NAME = "main"
        $ENV:GITHUB_API_URL = ''
        $ENV:GITHUB_REPOSITORY = ''
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_ENV = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_WORKSPACE = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
        New-Item -Path $env:GITHUB_WORKSPACE -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $env:GITHUB_WORKSPACE '.github') -ItemType Directory | Out-Null
    }

    AfterEach {
        Remove-Item $env:GITHUB_OUTPUT
        Remove-Item $env:GITHUB_ENV
        Remove-Item $env:GITHUB_WORKSPACE -Recurse -Force
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "DeploymentEnvironmentsJson" = "The JSON representation of the environment that are suitable for deployment"
            "UnknownEnvironment" = "Flag determining whether the environment is unknown"
            "GenerateALDocArtifact" = "Flag determining whether to generate the ALDoc artifact"
            "DeployALDocArtifact" = "Flag determining whether to deploy the ALDoc artifact to GitHub Pages"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    # 2 environments defined in GitHub - no branch policy
    It 'Test calling action directly - 2 environments defined in GitHub - no branch policy' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() }, @{ "name" = "another"; "protection_rules" = @() } ) })}
        }

        $deployToTestSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $deployToAnotherSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false }; "DeployTotest" = $deployToTestSettings; "DeployToAnother" = $deployToAnotherSettings } | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 2
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        $deploymentEnvironments.environments[1].environmentName | Should -Be 'another'
        $deploymentEnvironments.environments[1].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[1].shell | Should -Be 'pwsh'

         . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'CD'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
    }

    # 2 environments defined in GitHub - one with branch policy = protected branches
    It 'Test calling action directly - 2 environments defined in GitHub - one with branch policy = protected branches' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @( @{ "type" = "branch_policy"}); "deployment_branch_policy" = @{ "protected_branches" = $true; "custom_branch_policies" = $false } }, @{ "name" = "another"; "protection_rules" = @() } ) })}
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/branches' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @( @{ "name" = "branch"; "protected" = $true }, @{ "name" = "main"; "protected" = $false } ))}
        }

        $deployToTestSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $deployToAnotherSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false }; "DeployTotest" = $deployToTestSettings; "DeployToAnother" = $deployToAnotherSettings } | ConvertTo-Json -Compress

        $env:GITHUB_REF_NAME = 'main' # This is not a protected branch, so the _test_ environment should not be included, while _another_ environment should be included (no branch policy)
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'another'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        Set-Variable -Name deploymentEnvironments -Value $null # clean up variable

        $env:GITHUB_REF_NAME = 'branch' # This is a protected branch, so the _test_ environment should be included. _another_ environment should not be included as it has no branch policy (in that case deployment is only allowed from _main_ branch)
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        Set-Variable -Name deploymentEnvironments -Value $null # clean up variable
    }

    # 2 environments defined in GitHub - one with branch policy = branch. the other with no branch policy
    It 'Test calling action directly - 2 environments defined in GitHub - one with branch policy = main' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @( @{ "type" = "branch_policy"}); "deployment_branch_policy" = @{ "protected_branches" = $false; "custom_branch_policies" = $true } }, @{ "name" = "another"; "protection_rules" = @() } ) })}
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/branches' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @( @{ "name" = "branch"; "protected" = $true }, @{ "name" = "main"; "protected" = $false } ))}
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/deployment-branch-policies' } -MockWith {
            return @{"Content" = (@{ "branch_policies" = @( @{ "name" = "branch" }, @{ "name" = "branch2" } ) } | ConvertTo-Json -Depth 99 -Compress)}
        }

        $deployToTestSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $deployToAnotherSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false }; "DeployTotest" = $deployToTestSettings; "DeployToAnother" = $deployToAnotherSettings } | ConvertTo-Json -Compress
        # Only another environment should be included when deploying from main

        $env:GITHUB_REF_NAME = 'main' # This is not a protected branch, so the _test_ environment should not be included, while _another_ environment should be included (no branch policy)
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'another'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        Set-Variable -Name deploymentEnvironments -Value $null # clean up variable


        $env:GITHUB_REF_NAME = 'branch' # Change branch to _branch_ - now only test environment should be included (due to branch policy)
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        Set-Variable -Name deploymentEnvironments -Value $null # clean up variable


        $env:GITHUB_REF_NAME = 'branch2' # Change branch to branch2 - test environment should still be included (due to branch policy)
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        Set-Variable -Name deploymentEnvironments -Value $null # clean up variable

        # Add Branch policy to settings to only allow branch to deploy to test environment - now no environments should be included
        $settings.DeployToTest.branches = @('branch')

        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 0
        $deploymentEnvironments.environments | Should -BeNullOrEmpty
        Set-Variable -Name deploymentEnvironments -Value $null # clean up variable

        # Change branch to branch - test environment should still be included (due to branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
    }

    # 2 environments defined in GitHub, 1 in settings - exclude another environment
    It 'Test calling action directly - 2 environments defined in GitHub, one in settings' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() }; @{ "name" = "another"; "protection_rules" = @() } ) })}
        }

        $deployToTestSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $deployToAnotherSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $deployTosettingsenvSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @("settingsenv"); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false }; "DeployTotest" = $deployToTestSettings; "DeployToAnother" = $deployToAnotherSettings; "DeployTosettingsenv" = $deployTosettingsenvSettings }
        $env:Settings = $settings | ConvertTo-Json -Compress

        # All 3 environments should be included
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 3
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 3
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        $deploymentEnvironments.environments[1].environmentName | Should -Be 'another'
        $deploymentEnvironments.environments[1].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[1].shell | Should -Be 'pwsh'
        $deploymentEnvironments.environments[2].environmentName | Should -Be 'settingsenv'
        $deploymentEnvironments.environments[2].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[2].shell | Should -Be 'pwsh'
        Set-Variable -Name deploymentEnvironments -Value $null # clean up variable


        # Exclude _another_ environment
        $settings.excludeEnvironments += @('another')
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 2
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 2
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        $deploymentEnvironments.environments[1].environmentName | Should -Be 'settingsenv'
        $deploymentEnvironments.environments[1].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[1].shell | Should -Be 'pwsh'

        # Add Branch policy to settings to only allow branch to deploy to _test_ environment
        $settings.DeployToTest.branches = @('branch')
        $settings.excludeEnvironments = @() # Clear exclude environments
        $env:GITHUB_REF_NAME = 'main'
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 2
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 2
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'another'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
        $deploymentEnvironments.environments[1].environmentName | Should -Be 'settingsenv'
        $deploymentEnvironments.environments[1].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[1].shell | Should -Be 'pwsh'

        # Changing branch to branch - now only test environment should be included (due to settings branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
    }

    # 2 environments defined in Settings - one PROD and one non-PROD (name based)
    It 'Test calling action directly - 2 environments defined in Settings - one PROD and one non-PROD (name based)' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            throw "Not supported"
        }

        # One PROD environment and one non-PROD environment - only non-PROD environment is selected for CD
        $deployToTestSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $deployToAnotherSettings = @{ "branches" = @(); "continuousDeployment" = $null; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @("test (PROD)","another"); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false }; "DeployTotest" = $deployToTestSettings; "DeployToAnother" = $deployToAnotherSettings }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'another'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'

        # Publish to test environment - test is included
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'Publish'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test (PROD)'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
    }

    # 2 environments defined in Settings - one PROD and one non-PROD (settings based)
    It 'Test calling action directly - 2 environments defined in Settings - one PROD and one non-PROD (settings based)' {       
        $deployToTestSettings = @{ "branches" = @(); "continuousDeployment" = $false; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
        $deployToAnotherSettings = @{ "branches" = @(); "continuousDeployment" = $true; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }    
        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @("test (PROD)","another"); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false }; "DeployTotest" = $deployToTestSettings; "DeployToAnother" = $deployToAnotherSettings }

        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            throw "Not supported"
        }

        # One PROD environment and one non-PROD environment - only non-PROD environment is selected for CD
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput

        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'another'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'

        # Publish to test environment - test is included
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'Publish'
        PassGeneratedOutput
        $deploymentEnvironments = $DeploymentEnvironmentsJson | ConvertFrom-Json
        $deploymentEnvironments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environmentCount | Should -Be 1
        $deploymentEnvironments.environments | Should -Not -BeNullOrEmpty
        $deploymentEnvironments.environments.Count | Should -Be 1
        $deploymentEnvironments.environments[0].environmentName | Should -Be 'test (PROD)'
        $deploymentEnvironments.environments[0].'runs-on' | Should -Be '["ubuntu-latest"]'
        $deploymentEnvironments.environments[0].shell | Should -Be 'pwsh'
    }
}
