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
    }


}
