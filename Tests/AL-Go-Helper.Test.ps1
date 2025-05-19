Describe "AL-Go-Helper tests" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')
    }

    It 'CheckAndCreateProjectFolder' {
        Mock Write-Host { }

        Push-Location

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
        Pop-Location
        Remove-Item -Path $tempName -Recurse -Force
    }

    It 'GetFoldersFromAllProjects' {
        Mock Write-Host { }
        Mock Out-Host { }

        $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        $githubFolder = Join-Path $tempName ".github"
        $projects = [ordered]@{
            "A" = @(
                "app1",
                "app2",
                "app1.test"
            )
            "projects/B" = @(
                "../../src/app3"
                "../../src/app4"
            )
            "projects/C" = @(
                "../../src/app3"
                "../../A/app1"
            )
        }
        foreach($project in $projects.Keys) {
            $projectFolder = Join-Path $tempName $project
            Write-Host $projectFolder
            New-Item $projectFolder -ItemType Directory | Out-Null
            $projectSettings = @{
                "appFolders" = @($projects[$project] | Where-Object { $_ -notlike '*.test' })
                "testFolders" = @($projects[$project] | Where-Object { $_ -like '*.test' })
            }
            $algoFolder = Join-Path $projectFolder $ALGoFolderName
            New-Item $algoFolder -ItemType Directory | Out-Null
            Set-Content -Path (Join-Path $algoFolder "settings.json") -value (ConvertTo-Json -InputObject $projectSettings)
            foreach($folder in $projects[$project]) {
                $folderPath = Join-Path $projectFolder $folder
                if (!(Test-Path $folderPath)) {
                    New-Item $folderPath -ItemType Directory | Out-Null
                    Set-Content -Path (Join-Path $folderPath "app.json") -Value '{"id": "123"}'
                }
            }
        }

        $repoSettings = @{
            "type" = "PTE"
        }
        New-Item $githubFolder -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $githubFolder "AL-Go-settings.json") -value (ConvertTo-Json -InputObject $repoSettings)

        $folders = GetFoldersFromAllProjects -baseFolder $tempName | Sort-Object
        $folders | Should -be @(
            "A$([System.IO.Path]::DirectorySeparatorChar)app1"
            "A$([System.IO.Path]::DirectorySeparatorChar)app1.test"
            "A$([System.IO.Path]::DirectorySeparatorChar)app2"
            "src$([System.IO.Path]::DirectorySeparatorChar)app3"
            "src$([System.IO.Path]::DirectorySeparatorChar)app4"
        )
    }
}

