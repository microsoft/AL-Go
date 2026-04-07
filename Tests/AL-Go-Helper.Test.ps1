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

    Describe 'Get-VersionNumber' {
        # All tests share the same baseline settings to verify each strategy picks the correct source
        BeforeEach {
            $baseSettings = @{
                appBuild = 42
                appRevision = 7
                artifact = "https://bcartifacts.azureedge.net/sandbox/24.5.26928.27583/us"
                repoVersion = "3.1.200"
            }
        }

        It 'Default versioning strategy returns settings appBuild and appRevision' {
            $baseSettings.versioningStrategy = 0
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy -1 extracts version from artifact URL' {
            $baseSettings.versioningStrategy = -1
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be "24.5"
            $result.BuildNumber | Should -Be 26928
            $result.RevisionNumber | Should -Be 27583
        }

        It 'Strategy 16 uses repoVersion for major.minor' {
            $baseSettings.versioningStrategy = 16
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be "3.1"
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 19 (16+3) gets build number from repoVersion' {
            $baseSettings.versioningStrategy = 19
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be "3.1"
            $result.BuildNumber | Should -Be 200
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 19 with two-digit repoVersion defaults build to 0 with warning' {
            $baseSettings.versioningStrategy = 19
            $baseSettings.repoVersion = "2.4"
            $result = Get-VersionNumber -Settings $baseSettings -WarningVariable warnings -WarningAction SilentlyContinue
            $result.MajorMinorVersion | Should -Be "2.4"
            $result.BuildNumber | Should -Be 0
        }

        It 'Strategy 17 (16+1) uses repoVersion for major.minor but does not override appBuild' {
            $baseSettings.versioningStrategy = 17
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be "3.1"
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 3 without bit 16 behaves like default' {
            $baseSettings.versioningStrategy = 3
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be 42
            $result.RevisionNumber | Should -Be 7
        }

        It 'Strategy 2 passes through date-based appBuild and appRevision' {
            $baseSettings.versioningStrategy = 2
            $baseSettings.appBuild = 20260313 # Simulate date-based build number
            $baseSettings.appRevision = 141450 # Simulate time-based revision number
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be 20260313 # Build number should be passed through unchanged
            $result.RevisionNumber | Should -Be 141450 # Revision number should be passed through unchanged
        }

        It 'Strategy 15 passes through max build value' {
            $baseSettings.versioningStrategy = 15
            $baseSettings.appBuild = [Int32]::MaxValue # Simulate max build number
            $baseSettings.appRevision = 100 # Simulate some revision number
            $result = Get-VersionNumber -Settings $baseSettings
            $result.MajorMinorVersion | Should -Be ""
            $result.BuildNumber | Should -Be ([Int32]::MaxValue) # Build number should be passed through unchanged
            $result.RevisionNumber | Should -Be 100 # Revision number should be passed through unchanged
        }
    }
}
