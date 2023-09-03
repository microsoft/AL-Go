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
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
            "EnvironmentsMatrixJson" = "The Environment matrix to use for the Deploy step in compressed JSON format"
            "DeploymentEnvironmentsJson" = "Deployment Environments with settings in compressed JSON format"
            "EnvironmentCount" = "Number of Deployment Environments"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    # 2 environments defined in GitHub - no branch policy
    It 'Test calling action directly - 2 environments defined in GitHub - no branch policy' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() }, @{ "name" = "another"; "protection_rules" = @() } ) })
        }

        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @(); "excludeEnvironments" = @( 'github_pages' ) } | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="another";"os"="[""ubuntu-latest""]"};@{"environment"="test";"os"="[""ubuntu-latest""]"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"test"=@{"EnvironmentType"="SaaS";"EnvironmentName"="test";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"SyncMode"=$null;"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")};"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"SyncMode"=$null;"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")}}
        $EnvironmentCount | Should -Be 2

        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="test";"os"="[""ubuntu-latest""]"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"test"=@{"EnvironmentType"="SaaS";"EnvironmentName"="test";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"SyncMode"=$null;"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")}}
        $EnvironmentCount | Should -Be 1
    }

    # 2 environments defined in GitHub - one with branch policy = protected branches
    It 'Test calling action directly - 2 environments defined in GitHub - one with branch policy = protected branches' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @( @{ "type" = "branch_policy"}); "deployment_branch_policy" = @{ "protected_branches" = $true; "custom_branch_policies" = $false } }, @{ "name" = "another"; "protection_rules" = @() } ) })
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/branches' } -MockWith {
            return (ConvertTo-Json -Compress -Depth 99 -InputObject @( @{ "name" = "branch"; "protected" = $true }, @{ "name" = "main"; "protected" = $false } ))
        }

        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @(); "excludeEnvironments" = @( 'github_pages' ) } | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="another";"os"="[""ubuntu-latest""]"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"SyncMode"=$null;"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")}}
        $EnvironmentCount | Should -Be 1

        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
    }

    # 2 environments defined in GitHub - one with branch policy = branch. the other with no branch policy
    It 'Test calling action directly - 2 environments defined in GitHub - one with branch policy = main' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @( @{ "type" = "branch_policy"}); "deployment_branch_policy" = @{ "protected_branches" = $false; "custom_branch_policies" = $true } }, @{ "name" = "another"; "protection_rules" = @() } ) })
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/branches' } -MockWith {
            return (ConvertTo-Json -Compress -Depth 99 -InputObject @( @{ "name" = "branch"; "protected" = $true }, @{ "name" = "main"; "protected" = $false } ))
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/deployment-branch-policies' } -MockWith {
            return @{ "branch_policies" = @( @{ "name" = "branch" }, @{ "name" = "branch2" } ) } | ConvertTo-Json -Depth 99 -Compress
        }

        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @(); "excludeEnvironments" = @( 'github_pages' ) } | ConvertTo-Json -Compress
        # Only another environment should be included when deploying from main
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="another";"os"="[""ubuntu-latest""]"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"SyncMode"=$null;"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")}}
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "another"

        # Change branch to branch - now only test environment should be included (due to branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"

        # Change branch to branch2 - test environment should still be included (due to branch policy)
        $env:GITHUB_REF_NAME = 'branch2'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"

        # Add Branch policy to settings to only allow branch to deploy to test environment - now no environments should be included
        $settings += @{
            "DeployToTest" = @{
                "Branches" = @("branch")
            }
        }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 0

        # Change branch to branch - test environment should still be included (due to branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"
    }

    # 2 environments defined in GitHub, 1 in settings - exclude another environment
    It 'Test calling action directly - 2 environments defined in GitHub, one in settings' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            return (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() }; @{ "name" = "another"; "protection_rules" = @() } ) })
        }

        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @("settingsenv"); "excludeEnvironments" = @( 'github_pages' ) }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 3

        # Exclude another environment
        $settings.excludeEnvironments += @('another')
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 2
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Not -Contain "another"

        # Add Branch policy to settings to only allow branch to deploy to test environment
        $settings += @{
            "DeployToTest" = @{
                "Branches" = @("branch")
            }
        }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "settingsenv"

        # Changing branch to branch - now only test environment should be included (due to settings branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"
    }

    # 2 environments defined in Settings - one PROD and one non-PROD (name based)
    It 'Test calling action directly - 2 environments defined in Settings - one PROD and one non-PROD (name based)' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            throw "Not supported"
        }

        # One PROD environment and one non-PROD environment - only non-PROD environment is selected for CD
        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @("test (PROD)","another"); "excludeEnvironments" = @( 'github_pages' ) }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "another"

        # Publish to test environment - test is included
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'Publish'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"
    }

    # 2 environments defined in Settings - one PROD and one non-PROD (settings based)
    It 'Test calling action directly - 2 environments defined in Settings - one PROD and one non-PROD (settings based)' {
        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @("test (PROD)","another"); "excludeEnvironments" = @( 'github_pages' ) }

        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments' } -MockWith {
            throw "Not supported"
        }

        $settings += @{
            "DeployToTest" = @{
                "ContinuousDeployment" = $false
            }
            "DeployToAnother" = @{
                "ContinuousDeployment" = $true
            }
        }

        # One PROD environment and one non-PROD environment - only non-PROD environment is selected for CD
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "another"

        # Publish to test environment - test is included
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'Publish'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"
    }
}