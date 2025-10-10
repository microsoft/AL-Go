Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/ReadSettings.psm1') -Force

InModuleScope ReadSettings { # Allows testing of private functions
    Describe "ReadSettings" {
        BeforeAll {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
            $schema = Get-Content -Path (Join-Path $PSScriptRoot '../Actions/.Modules/settings.schema.json') -Raw
        }

        It 'Reads settings from all settings locations' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $ALGoFolder = Join-Path $tempName $ALGoFolderName
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $ALGoFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            New-Item -Path (Join-Path $tempName "projectx/$ALGoFolderName") -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $tempName "projecty/$ALGoFolderName") -ItemType Directory | Out-Null

            # Create settings files
            # Property:    Repo:               Project (single):   Project (multi):    Workflow:           Workflow:           User:
            #                                                                                              if(branch=dev):
            # Property1    repo1               single1             multi1                                  branch1             user1
            # Property2    repo2                                                       workflow2
            # Property3    repo3
            # Arr1         @("repo1","repo2")
            # Property4                        single4                                                     branch4
            # property5                                            multi5
            # property6                                                                                                        user6
            @{ "property1" = "repo1"; "property2" = "repo2"; "property3" = "repo3"; "arr1" = @("repo1", "repo2") } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -encoding utf8 -Force
            @{ "property1" = "single1"; "property4" = "single4" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $ALGoFolder "settings.json") -encoding utf8 -Force
            @{ "property1" = "multi1"; "property5" = "multi5" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -encoding utf8 -Force
            @{ "property2" = "workflow2"; "conditionalSettings" = @( @{ "branches" = @( 'dev' ); "settings" = @{ "property1" = "branch1"; "property4" = "branch4" } } ) } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "Workflow.settings.json") -encoding utf8 -Force
            @{ "property1" = "user1"; "property6" = "user6" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "user.settings.json") -encoding utf8 -Force

            # No settings variables
            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            # Repo only
            $repoSettings = ReadSettings -baseFolder $tempName -project '' -repoName 'repo' -workflowName '' -branchName '' -userName ''
            $repoSettings.property1 | Should -Be 'repo1'
            $repoSettings.property2 | Should -Be 'repo2'
            $repoSettings.property3 | Should -Be 'repo3'

            # Repo + single project
            $singleProjectSettings = ReadSettings -baseFolder $tempName -project '.' -repoName 'repo' -workflowName '' -branchName '' -userName ''
            $singleProjectSettings.property1 | Should -Be 'single1'
            $singleProjectSettings.property2 | Should -Be 'repo2'
            $singleProjectSettings.property4 | Should -Be 'single4'

            # Repo + multi project
            $multiProjectSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName ''
            $multiProjectSettings.property1 | Should -Be 'multi1'
            $multiProjectSettings.property2 | Should -Be 'repo2'
            $multiProjectSettings.property5 | Should -Be 'multi5'

            # Repo + workflow
            $workflowRepoSettings = ReadSettings -baseFolder $tempName -project '' -repoName 'repo' -workflowName 'Workflow' -branchName '' -userName ''
            $workflowRepoSettings.property1 | Should -Be 'repo1'
            $workflowRepoSettings.property2 | Should -Be 'workflow2'

            # Repo + single project + workflow
            $workflowSingleSettings = ReadSettings -baseFolder $tempName -project '.' -repoName 'repo' -workflowName 'Workflow' -branchName '' -userName ''
            $workflowSingleSettings.property1 | Should -Be 'single1'
            $workflowSingleSettings.property2 | Should -Be 'workflow2'
            $workflowSingleSettings.property4 | Should -Be 'single4'
            $workflowSingleSettings.property3 | Should -Be 'repo3'

            # Repo + multi project + workflow + dev branch
            $workflowMultiSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName ''
            $workflowMultiSettings.property1 | Should -Be 'branch1'
            $workflowMultiSettings.property2 | Should -Be 'workflow2'
            $workflowMultiSettings.property3 | Should -Be 'repo3'
            $workflowMultiSettings.property4 | Should -Be 'branch4'
            $workflowMultiSettings.property5 | Should -Be 'multi5'
            $workflowMultiSettings.property6 | Should -BeNullOrEmpty

            # Repo + multi project + workflow + dev branch + user
            $userWorkflowMultiSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user'
            $userWorkflowMultiSettings.property1 | Should -Be 'user1'
            $userWorkflowMultiSettings.property2 | Should -Be 'workflow2'
            $userWorkflowMultiSettings.property3 | Should -Be 'repo3'
            $userWorkflowMultiSettings.property4 | Should -Be 'branch4'
            $userWorkflowMultiSettings.property5 | Should -Be 'multi5'
            $userWorkflowMultiSettings.property6 | Should -Be 'user6'

            # Org settings variable
            # property 2 = orgsetting2
            # property 7 = orgsetting7
            # arr1 = @(org3) - gets merged
            $ENV:ALGoOrgSettings = @{ "property2" = "orgsetting2"; "property7" = "orgsetting7"; "arr1" = @("org3") } | ConvertTo-Json -Depth 99

            # Org(var) + Repo + multi project + workflow + dev branch + user
            $withOrgSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user'
            $withOrgSettings.property1 | Should -Be 'user1'
            $withOrgSettings.property2 | Should -Be 'workflow2'
            $withOrgSettings.property3 | Should -Be 'repo3'
            $withOrgSettings.property4 | Should -Be 'branch4'
            $withOrgSettings.property5 | Should -Be 'multi5'
            $withOrgSettings.property6 | Should -Be 'user6'
            $withOrgSettings.property7 | Should -Be 'orgsetting7'
            $withOrgSettings.arr1 | Should -Be @("org3", "repo1", "repo2")

            # Repo settings variable
            # property3 = reposetting3
            # property8 = reposetting8
            $ENV:ALGoRepoSettings = @{ "property3" = "reposetting3"; "property8" = "reposetting8" } | ConvertTo-Json -Depth 99

            # Org(var) + Repo + Repo(var) + multi project + workflow + dev branch + user
            $withRepoSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user'
            $withRepoSettings.property1 | Should -Be 'user1'
            $withRepoSettings.property2 | Should -Be 'workflow2'
            $withRepoSettings.property3 | Should -Be 'reposetting3'
            $withRepoSettings.property4 | Should -Be 'branch4'
            $withRepoSettings.property5 | Should -Be 'multi5'
            $withRepoSettings.property6 | Should -Be 'user6'
            $withRepoSettings.property7 | Should -Be 'orgsetting7'
            $withRepoSettings.property8 | Should -Be 'reposetting8'

            # Add conditional settings as repo(var) settings
            $conditionalSettings = [ordered]@{
                "conditionalSettings" = @(
                    @{
                        "branches" = @( 'branchx', 'branchy' )
                        "settings" = @{ "property3" = "branchxy"; "property4" = "branchxy" }
                    }
                    @{
                        "repositories" = @( 'repox', 'repoy' )
                        "settings"     = @{ "property3" = "repoxy"; "property4" = "repoxy" }
                    }
                    @{
                        "projects" = @( 'projectx', 'projecty' )
                        "settings" = @{ "property3" = "projectxy"; "property4" = "projectxy" }
                    }
                    @{
                        "workflows" = @( 'workflowx', 'workflowy' )
                        "settings"  = @{ "property3" = "workflowxy"; "property4" = "workflowxy" }
                    }
                    @{
                        "users"    = @( 'userx', 'usery' )
                        "settings" = @{ "property3" = "userxy"; "property4" = "userxy" }
                    }
                    @{
                        "branches" = @( 'branchx', 'branchy' )
                        "projects" = @( 'projectx', 'projecty' )
                        "settings" = @{ "property3" = "bpxy"; "property4" = "bpxy" }
                    }
                )
            }
            $ENV:ALGoRepoSettings = $conditionalSettings | ConvertTo-Json -Depth 99

            # Test that conditional settings are applied correctly
            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'branchy' -userName 'user'
            $conditionalSettings.property3 | Should -Be 'branchxy'
            $conditionalSettings.property4 | Should -Be 'branchxy'

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repox' -workflowName 'Workflow' -branchName 'dev' -userName 'user'
            $conditionalSettings.property3 | Should -Be 'repoxy'
            $conditionalSettings.property4 | Should -Be 'branch4'

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'projectx' -repoName 'repo' -workflowName 'Workflow' -branchName 'branch' -userName 'user'
            $conditionalSettings.property3 | Should -Be 'projectxy'
            $conditionalSettings.property4 | Should -Be 'projectxy'

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'projectx' -repoName 'repo' -workflowName 'Workflowx' -branchName 'branch' -userName 'user'
            $conditionalSettings.property3 | Should -Be 'workflowxy'
            $conditionalSettings.property4 | Should -Be 'workflowxy'

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'branch' -userName 'usery'
            $conditionalSettings.property3 | Should -Be 'userxy'
            $conditionalSettings.property4 | Should -Be 'userxy'

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'projecty' -repoName 'repo' -workflowName 'Workflow' -branchName 'branchx' -userName 'user'
            $conditionalSettings.property3 | Should -Be 'bpxy'
            $conditionalSettings.property4 | Should -Be 'bpxy'

            # Invalid Org(var) setting should throw
            $ENV:ALGoOrgSettings = 'this is not json'
            { ReadSettings -baseFolder $tempName -project 'Project' } | Should -Throw

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'Settings schema is valid' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            Test-Json -json $schema | Should -Be $true
        }

        It 'All default settings are in the schema' {
            $defaultSettings = GetDefaultSettings

            $schemaObj = $schema | ConvertFrom-Json

            $defaultSettings.Keys | ForEach-Object {
                $property = $_
                $schemaObj.properties.PSObject.Properties.Name | Should -Contain $property
            }
        }

        It 'Default settings match schema' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            $defaultSettings = GetDefaultSettings
            Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema | Should -Be $true
        }

        It 'Shell setting can only be pwsh or powershell' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            $defaultSettings = GetDefaultSettings
            $defaultSettings.shell = 42
            try {
                Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema
            }
            catch {
                $_.Exception.Message | Should -Be "The JSON is not valid with the schema: Value is `"integer`" but should be `"string`" at '/shell'"
            }

            $defaultSettings.shell = "random"
            try {
                Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema
            }
            catch {
                $_.Exception.Message | Should -Be "The JSON is not valid with the schema: The string value is not a match for the indicated regular expression at '/shell'"
            }
        }

        It 'Projects setting is an array of strings' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            # If the projects setting is not an array, it should throw an error
            $defaultSettings = GetDefaultSettings
            $defaultSettings.projects = "not an array"
            try {
                Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema
            }
            catch {
                $_.Exception.Message | Should -Be "The JSON is not valid with the schema: Value is `"string`" but should be `"array`" at '/projects'"
            }

            # If the projects setting is an array, but contains non-string values, it should throw an error
            $defaultSettings.projects = @("project1", 42)
            try {
                Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema
            }
            catch {
                $_.Exception.Message | Should -Be "The JSON is not valid with the schema: Value is `"integer`" but should be `"string`" at '/projects/1'"
            }

            # If the projects setting is an array of strings, it should pass the schema validation
            $defaultSettings.projects = @("project1")
            Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema | Should -Be $true
            $defaultSettings.projects = @("project1", "project2")
            Test-Json -json (ConvertTo-Json $defaultSettings) -schema $schema | Should -Be $true
        }

        It 'overwriteSettings property resets settings from destination object (simple types)' {
            $dst = [ordered]@{
                setting1 = "value1"
                setting2 = "value2"
                setting3 = "value3"
            }
            $src = [PSCustomObject]@{
                overwriteSettings = @("setting1","setting2","setting4") # setting2 exist in the dst, but there no value in src, should be ignored; setting4 does not exist in dst, should be ignored;
                setting1     = "newvalue1"
                setting5     = "value5"
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src

            $dst.setting1 | Should -Be 'newvalue1'   # Updated value
            $dst.setting2 | Should -Be 'value2'      # Unchanged
            $dst.setting3 | Should -Be 'value3'      # Unchanged
            $dst.setting4 | Should -BeNullOrEmpty    # Did not exist, still does not exist
            $dst.setting5 | Should -Be 'value5'      # New setting added

            # overwriteSettings should never be added to the destination object
            $dst.PSObject.Properties.Name | Should -Not -Contain 'overwriteSettings'
        }

        It 'overwriteSettings property resets settings from destination object (complex types: arrays)' {
            # overwriteSettings should work for complex types (arrays)
            $dst = [ordered]@{
                complexSetting = @( "value1", "value2", "value3" )
                setting3 = "value3"
            }

            $src = [PSCustomObject]@{
                complexSetting = @( "newvalue1", "newvalue2" )
                setting5 = "value5"
            }

            # Without using overwriteSettings, the complex settings are merged, not overwritten
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src

            $dst.complexSetting | Should -Be @("value1", "value2", "value3", "newvalue1", "newvalue2") # Merged
            $dst.setting3 | Should -Be 'value3'             # Unchanged
            $dst.setting5 | Should -Be 'value5'             # New setting added

            # overwriteSettings should never be added to the destination object
            $dst.PSObject.Properties.Name | Should -Not -Contain 'overwriteSettings'

            # Now use overwriteSettings to overwrite the complex setting
            $dst = [ordered]@{
                complexSetting = @( "value1", "value2", "value3" )
                setting3 = "value3"
            }

            $src = [PSCustomObject]@{
                overwriteSettings = @("complexSetting")
                complexSetting = @( "newvalue1", "newvalue2" )
                setting5 = "value5"
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src

            $dst.complexSetting | Should -Be @("newvalue1", "newvalue2") # Overwritten
            $dst.setting3 | Should -Be 'value3'             # Unchanged
            $dst.setting5 | Should -Be 'value5'             # New setting added

            # overwriteSettings should never be added to the destination object
            $dst.PSObject.Properties.Name | Should -Not -Contain 'overwriteSettings'
        }

        It 'overwriteSettings property resets settings from destination object (complex types: objects)' {
            # overwriteSettings should work for complex types (objects)
            $dst = [ordered]@{
                complexSetting = [ordered]@{
                    setting1 = "value1"
                    setting2 = "value2"
                    setting3 = "value3"
                }
                setting4 = "value4"
            }

            $src = [PSCustomObject]@{
                complexSetting = [PSCustomObject]@{
                    setting1 = "newvalue1"
                    setting2 = "newvalue2"
                    setting5 = "value5"
                }
                setting6 = "value6"
            }

            # Without using overwriteSettings, the complex settings are merged, not replaced
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src

            $dst.complexSetting.setting1 | Should -Be 'newvalue1'   # Updated value
            $dst.complexSetting.setting2 | Should -Be 'newvalue2'   # Updated value
            $dst.complexSetting.setting3 | Should -Be 'value3'      # Unchanged
            $dst.complexSetting.setting5 | Should -Be 'value5'      # New setting added
            $dst.setting4 | Should -Be 'value4'                     # Unchanged
            $dst.setting6 | Should -Be 'value6'                     # New setting added

            # Now use overwriteSettings to replace the complex setting
            $dst = [ordered]@{
                complexSetting = [PSCustomObject]@{
                    setting1 = "value1"
                    setting2 = "value2"
                    setting3 = "value3"
                }
                setting4 = "value4"
            }

            $src = [PSCustomObject]@{
                overwriteSettings = @("complexSetting")
                complexSetting = [PSCustomObject]@{
                    setting1 = "newvalue1"
                    setting2 = "newvalue2"
                    setting5 = "value5"
                }
                setting6 = "value6"
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src

            $dst.complexSetting.setting1 | Should -Be 'newvalue1'   # Updated value
            $dst.complexSetting.setting2 | Should -Be 'newvalue2'   #
            $dst.complexSetting.setting3 | Should -BeNullOrEmpty    # Removed
            $dst.complexSetting.setting5 | Should -Be 'value5'      # New setting added
            $dst.setting4 | Should -Be 'value4'                     # Unchanged
            $dst.setting6 | Should -Be 'value6'                     # New setting added

            # overwriteSettings should never be added to the destination object
            $dst.PSObject.Properties.Name | Should -Not -Contain 'overwriteSettings'
        }

        It 'overwriteSettings property does not reset a setting if it does not exist in the source object' {
            $dst = [ordered]@{
                setting1 = @("value1.0", "value1.1")
                setting2 = @("value2.0", "value2.1")
            }
            $src = [PSCustomObject]@{
                overwriteSettings = @("setting2") # setting2 does not exist in src, should be ignored
                setting1     = @("newvalue1.2", "newvalue1.3")
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src

            $dst.setting1 | Should -Be @('value1.0', 'value1.1', 'newvalue1.2', 'newvalue1.3') # Merged
            $dst.setting2 | Should -Be @('value2.0', 'value2.1')                           # Unchanged

            # overwriteSettings should never be added to the destination object
            $dst.PSObject.Properties.Name | Should -Not -Contain 'overwriteSettings'
        }
    }
}
