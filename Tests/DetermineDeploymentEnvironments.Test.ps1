Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force

Describe "DetermineDeploymentEnvironments Action Test" {
    BeforeAll {
        $actionName = "DetermineDeploymentEnvironments"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
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
        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @(); "excludeEnvironments" = @( 'github_pages' ) } | ConvertTo-Json -Compress

        Mock InvokeWebRequest {
            if ($uri -like '*/environments') { return (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() }, @{ "name" = "another"; "protection_rules" = @() } ) }) }
        }

        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*'

        PassGeneratedOutput

        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="test";"os"="[""ubuntu-latest""]"};@{"environment"="another";"os"="[""ubuntu-latest""]"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"test"=@{"EnvironmentType"="SaaS";"EnvironmentName"="test";"Branches"=$null;"BranchesFromPolicy"=$null;"Projects"="*";"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")};"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=$null;"BranchesFromPolicy"=$null;"Projects"="*";"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")}}
        $EnvironmentCount | Should -Be 2

        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test'

        PassGeneratedOutput

        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="test";"os"="[""ubuntu-latest""]"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"test"=@{"EnvironmentType"="SaaS";"EnvironmentName"="test";"Branches"=$null;"BranchesFromPolicy"=$null;"Projects"="*";"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")}}
        $EnvironmentCount | Should -Be 1
    }

    # 2 environments defined in GitHub - one with branch policy
    It 'Test calling action directly - 2 environments defined in GitHub - one with branch policy' {
        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "environments" = @(); "excludeEnvironments" = @( 'github_pages' ) } | ConvertTo-Json -Compress

        Mock InvokeWebRequest {
            if ($uri -like '*/environments') { return (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @( @{ "type" = "branch_policy"}); "deployment_branch_policy" = @{ "protected_branches" = $true } }, @{ "name" = "another"; "protection_rules" = @() } ) }) }
            if ($uri -like '*/branches') { return (ConvertTo-Json -Compress -Depth 99 -InputObject @( @{ "name" = "branch"; "protected" = $true }, @{ "name" = "main"; "protected" = $false } )) }
            #if ($uri -like '*/deployment-branch-policies') { return @{ "branch_policies" = @( @{ "name" = "main" }, @{ "name" = "branch" } ) } | ConvertTo-Json -Depth 99 -Compress }
        }

        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*'

        PassGeneratedOutput

        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="another";"os"="[""ubuntu-latest""]"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=$null;"BranchesFromPolicy"=$null;"Projects"="*";"ContinuousDeployment"=$null;"runs-on"=@("ubuntu-latest")}}
        $EnvironmentCount | Should -Be 1

        $env:GITHUB_REF_NAME = 'branch'

        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*'

        PassGeneratedOutput

        $EnvironmentCount | Should -Be 1
    }
}