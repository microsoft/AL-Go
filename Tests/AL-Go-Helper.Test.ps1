Describe "RunPipeline Action Tests" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')
    }

    It 'MergeCustomObjectIntoOrderedDictionary' {
        # This function is used to merge settings files into the settings object
        # dest is the default settings object
        $dest = [ordered]@{
            'int0' = 0
            'int1' = 1
            'int2' = 2
            'str1' = 'str1'
            'str2' = 'str2'
            'arr1' = @('a', 'b', 'c')
            'arr2' = @('a', 'b', 'c')
            'obj1' = [ordered]@{
                'a' = 'a'
                'b' = 'b'
                'c' = 'c'
            }
            'obj2' = [ordered]@{
                'a' = 'a'
                'b' = 'b'
                'c' = 'c'
            }
            'objarr1' = @([ordered]@{'a' = 'a'; 'b' = 'b'; 'c' = 'c'}, [ordered]@{'d' = 'd'; 'e' = 'e'; 'f' = 'f'})
            'objarr2' = @([ordered]@{'a' = 'a'; 'b' = 'b'; 'c' = 'c'}, [ordered]@{'d' = 'd'; 'e' = 'e'; 'f' = 'f'})
        }

        $dest.Count | Should -Be 11

        # source is the settings read from a file
        $src = @{
            'int1' = [Int64]::MaxValue
            'int2' = 3
            'int3' = 4
            'objarr2' = @([ordered]@{'g' = 'g'; 'h' = 'h'; 'i' = 'i'}, [ordered]@{'d' = 'd'; 'e' = 'e'; 'f' = 'f'})
            'objarr3' = @([ordered]@{'g' = 'g'; 'h' = 'h'; 'i' = 'i'}, [ordered]@{'j' = 'j'; 'k' = 'k'; 'l' = 'l'})
        } | ConvertTo-Json | ConvertFrom-Json
        $src.int2 = [Int32]3
        $src.int3 = [Int32]4
        
        # Merge the settings
        MergeCustomObjectIntoOrderedDictionary -dst $dest -src $src
        $dest.Count | Should -Be 13
        $dest['int0'] | Should -Be 0
        $dest['int1'] | Should -Be ([Int64]::MaxValue)
        $dest['int2'] | Should -Be 3
        $dest['int3'] | Should -Be 4
        $dest['objarr2'] | ConvertTo-Json | Should -Be (@([ordered]@{'a' = 'a'; 'b' = 'b'; 'c' = 'c'}, [ordered]@{'d' = 'd'; 'e' = 'e'; 'f' = 'f'}, [ordered]@{'g' = 'g'; 'h' = 'h'; 'i' = 'i'}, [ordered]@{'d' = 'd'; 'e' = 'e'; 'f' = 'f'}) | ConvertTo-Json)
        $dest['objarr3'] | ConvertTo-Json | Should -Be (@([ordered]@{'g' = 'g'; 'h' = 'h'; 'i' = 'i'}, [ordered]@{'j' = 'j'; 'k' = 'k'; 'l' = 'l'}) | ConvertTo-Json)

        # source is the settings read from a file
        # Check that multiple settings files are merged correctly one after the other
        $src = @{
            'str2' = 'str3'
            'str3' = 'str4'
            'arr2' = @('c', 'd', 'e')
            'arr3' = @('c', 'd', 'e')
            'obj2' = [ordered]@{'c' = 'c'; 'd' = 'd'; 'e' = 'e'}
            'obj3' = [ordered]@{'d' = 'd'; 'e' = 'e'; 'f' = 'f'}
        } | ConvertTo-Json | ConvertFrom-Json
        
        # Check that applying the same settings twice doesn't change the result
        1..2 | ForEach-Object {
            MergeCustomObjectIntoOrderedDictionary -dst $dest -src $src
            $dest.Count | Should -Be 16
            $dest['int0'] | Should -Be 0
            $dest['int1'] | Should -Be ([Int64]::MaxValue)
            $dest['int2'] | Should -Be 3
            $dest['int3'] | Should -Be 4
            $dest['str2'] | Should -Be 'str3'
            $dest['str3'] | Should -Be 'str4'
            $dest['arr2'] | Should -Be @('a', 'b', 'c', 'd', 'e')
            $dest['arr3'] | Should -Be @('c', 'd', 'e')
            $dest['obj2'] | ConvertTo-Json | Should -Be ([ordered]@{'a' = 'a'; 'b' = 'b'; 'c' = 'c'; 'd' = 'd'; 'e' = 'e'} | ConvertTo-Json)
            $dest['obj3'] | ConvertTo-Json | Should -Be ([ordered]@{'d' = 'd'; 'e' = 'e'; 'f' = 'f'} | ConvertTo-Json)
        }
    }

    It 'ReadSettings' {
        $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        $githubFolder = Join-Path $tempName ".github"
        $ALGoFolder = Join-Path $tempName $ALGoFolderName
        $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

        New-Item $githubFolder -ItemType Directory | Out-Null
        New-Item $ALGoFolder -ItemType Directory | Out-Null
        New-Item $projectALGoFolder -ItemType Directory | Out-Null

        @{ "property1" = "repo1"; "property2" = "repo2"; "property3" = "repo3" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -encoding utf8 -Force
        @{ "property1" = "single1"; "property4" = "single4" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $ALGoFolder "settings.json") -encoding utf8 -Force
        @{ "property1" = "multi1"; "property5" = "multi5" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -encoding utf8 -Force
        @{ "property2" = "workflow2"; "conditionalSettings" = @{ "branches" = @( 'dev' ); "settings" = @{ "property1" = "branch1"; "property4" = "branch4" } } } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "Workflow.settings.json") -encoding utf8 -Force
        @{ "property1" = "user1"; "property6" = "user6" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "user.settings.json") -encoding utf8 -Force

        $repoSettings = ReadSettings -baseFolder $tempName -project '' -repoName 'repo' -workflowName '' -branchName '' -userName ''
        $repoSettings.property1 | Should -Be 'repo1'
        $repoSettings.property2 | Should -Be 'repo2'
        $repoSettings.property3 | Should -Be 'repo3'

        $singleProjectSettings = ReadSettings -baseFolder $tempName -project '.' -repoName 'repo' -workflowName '' -branchName '' -userName ''
        $singleProjectSettings.property1 | Should -Be 'single1'
        $singleProjectSettings.property2 | Should -Be 'repo2'
        $singleProjectSettings.property4 | Should -Be 'single4'

        $multiProjectSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName ''
        $multiProjectSettings.property1 | Should -Be 'multi1'
        $multiProjectSettings.property2 | Should -Be 'repo2'
        $multiProjectSettings.property5 | Should -Be 'multi5'

        $workflowRepoSettings = ReadSettings -baseFolder $tempName -project '' -repoName 'repo' -workflowName 'Workflow' -branchName '' -userName ''
        $workflowRepoSettings.property1 | Should -Be 'repo1'
        $workflowRepoSettings.property2 | Should -Be 'workflow2'

        $workflowSingleSettings = ReadSettings -baseFolder $tempName -project '.' -repoName 'repo' -workflowName 'Workflow' -branchName '' -userName ''
        $workflowSingleSettings.property1 | Should -Be 'single1'
        $workflowSingleSettings.property2 | Should -Be 'workflow2'
        $workflowSingleSettings.property4 | Should -Be 'single4'
        $workflowSingleSettings.property3 | Should -Be 'repo3'

        $workflowMultiSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName ''
        $workflowMultiSettings.property1 | Should -Be 'branch1'
        $workflowMultiSettings.property2 | Should -Be 'workflow2'
        $workflowMultiSettings.property3 | Should -Be 'repo3'
        $workflowMultiSettings.property4 | Should -Be 'branch4'
        $workflowMultiSettings.property5 | Should -Be 'multi5'

        $userWorkflowMultiSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user'
        $userWorkflowMultiSettings.property1 | Should -Be 'user1'
        $userWorkflowMultiSettings.property2 | Should -Be 'workflow2'
        $userWorkflowMultiSettings.property3 | Should -Be 'repo3'
        $userWorkflowMultiSettings.property4 | Should -Be 'branch4'
        $userWorkflowMultiSettings.property5 | Should -Be 'multi5'

        # Clean up
        Remove-Item -Path $tempName -Recurse -Force
    }

    It 'CheckAndCreateProjectFolder' {
        Mock Write-Host { }

        # Create a temp folder with the PTE template files
        $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        New-Item $tempName -ItemType Directory | Out-Null
        $repoName = "Per Tenant Extension"
        $pteTemplateFiles = Join-Path $PSScriptRoot "../Templates/$repoName" -Resolve
        Copy-Item -Path $pteTemplateFiles -Destination $tempName -Recurse -Force
        $repoFolder = Join-Path $tempName $repoName
        $repoFolder | Should -Exist
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Exist
        Set-Location $repoFolder

        # Test without project name - should not change the repo
        CheckAndCreateProjectFolder -project '.'
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Exist
        CheckAndCreateProjectFolder -project ''
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Exist

        # Create an app in an empty repo
        New-Item -Path 'App' -ItemType Directory | Out-Null
        Set-Content -Path 'App/app.json' -Value '{"id": "123"}'

        # Creating a project in a single project repo with apps should fail
        { CheckAndCreateProjectFolder -project 'project1' } | Should -Throw

        # Remove app folder and try again
        Remove-Item -Path 'App' -Recurse -Force

        # Creating a project in a single project repo without apps should succeed
        { CheckAndCreateProjectFolder -project 'project1' } | Should -Not -Throw

        # .AL-Go folder should be moved to the project folder
        Join-Path $repoFolder '.AL-Go/settings.json' | Should -Not -Exist
        Join-Path '.' '.AL-Go/settings.json' | Should -Exist
        'project1.code-workspace' | Should -Exist

        # If repo is setup for multiple projects, using an empty project name should fail
        Set-Location $repoFolder
        { CheckAndCreateProjectFolder -project '' } | Should -Throw

        # Creating a second project should not fail
        { CheckAndCreateProjectFolder -project 'project2' } | Should -Not -Throw
        Join-Path $repoFolder 'project2/.AL-Go/settings.json' | Should -Exist
        Join-Path $repoFolder 'project2/project2.code-workspace' | Should -Exist

        # Clean up
        Remove-Item -Path $tempName -Recurse -Force
    }
}
