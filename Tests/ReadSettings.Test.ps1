Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/ReadSettings.psm1') -Force

InModuleScope ReadSettings { # Allows testing of private functions
    Describe 'ReadSettings' {
        BeforeAll {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
            $schema = Get-Content -Path (Join-Path $PSScriptRoot '../Actions/.Modules/settings.schema.json') -Raw
        }

        BeforeEach {
            $originalOrgSettings = $ENV:ALGoOrgSettings
            $originalRepoSettings = $ENV:ALGoRepoSettings
        }

        AfterEach {
            $ENV:ALGoOrgSettings = $originalOrgSettings
            $ENV:ALGoRepoSettings = $originalRepoSettings
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
                        "triggers" = @( 'schedule', 'workflow_dispatch' )
                        "settings" = @{ "property3" = "triggerxy"; "property4" = "triggerxy" }
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
            $previousGitHubEventName = $ENV:GITHUB_EVENT_NAME
            $ENV:GITHUB_EVENT_NAME = 'push'

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

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'branch' -userName 'user' -trigger 'schedule'
            $conditionalSettings.property3 | Should -Be 'triggerxy'
            $conditionalSettings.property4 | Should -Be 'triggerxy'

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'branch' -userName 'user' -trigger 'workflow_dispatch'
            $conditionalSettings.property3 | Should -Be 'triggerxy'
            $conditionalSettings.property4 | Should -Be 'triggerxy'

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'branch' -userName 'user' -trigger 'push'
            $conditionalSettings.property3 | Should -Be 'repo3'
            $conditionalSettings.property4 | Should -BeNullOrEmpty

            $conditionalSettings = ReadSettings -baseFolder $tempName -project 'projecty' -repoName 'repo' -workflowName 'Workflow' -branchName 'branchx' -userName 'user'
            $conditionalSettings.property3 | Should -Be 'bpxy'
            $conditionalSettings.property4 | Should -Be 'bpxy'

            $ENV:GITHUB_EVENT_NAME = $previousGitHubEventName

            # Invalid Org(var) setting should throw
            $ENV:ALGoOrgSettings = 'this is not json'
            { ReadSettings -baseFolder $tempName -project 'Project' } | Should -Throw

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            # Test customSettings parameter - should have highest precedence
            # customSettings overrides all other settings (including user settings)
            $customSettingsJson = @{ "property1" = "custom1"; "property2" = "custom2"; "property9" = "custom9" } | ConvertTo-Json -Depth 99
            $customSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user' -customSettings $customSettingsJson
            $customSettings.property1 | Should -Be 'custom1'    # Overrides user setting
            $customSettings.property2 | Should -Be 'custom2'    # Overrides workflow setting
            $customSettings.property3 | Should -Be 'repo3'      # Unchanged (not in custom settings)
            $customSettings.property4 | Should -Be 'branch4'    # Unchanged (not in custom settings)
            $customSettings.property5 | Should -Be 'multi5'     # Unchanged (not in custom settings)
            $customSettings.property6 | Should -Be 'user6'      # Unchanged (not in custom settings)
            $customSettings.property9 | Should -Be 'custom9'    # New property from custom settings

            # Test customSettings with empty string (should not affect existing behavior)
            $emptyCustomSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user' -customSettings ''
            $emptyCustomSettings.property1 | Should -Be 'user1'      # Same as without custom settings
            $emptyCustomSettings.property2 | Should -Be 'workflow2'  # Same as without custom settings
            $emptyCustomSettings.property3 | Should -Be 'repo3'      # Same as without custom settings

            # Test customSettings with array merging
            $customArraySettingsJson = @{ "arr1" = @("custom1", "custom2") } | ConvertTo-Json -Depth 99
            $customArraySettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user' -orgSettingsVariableValue (@{ "arr1" = @("org3") } | ConvertTo-Json -Depth 99) -customSettings $customArraySettingsJson
            $customArraySettings.arr1 | Should -Be @("org3", "repo1", "repo2", "custom1", "custom2")  # Custom values are merged at the end

            # Test customSettings with overwriteSettings to replace arrays
            $customOverwriteSettingsJson = @{ "overwriteSettings" = @("arr1"); "arr1" = @("customonly1", "customonly2") } | ConvertTo-Json -Depth 99
            $customOverwriteSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user' -orgSettingsVariableValue (@{ "arr1" = @("org3") } | ConvertTo-Json -Depth 99) -customSettings $customOverwriteSettingsJson
            $customOverwriteSettings.arr1 | Should -Be @("customonly1", "customonly2")  # Array completely replaced by custom settings

            # Test invalid customSettings JSON should throw
            { ReadSettings -baseFolder $tempName -project 'Project' -customSettings 'invalid json' } | Should -Throw

            # Test customSettings with complex object
            $customComplexSettingsJson = @{
                "deliverToAppSource" = @{
                    "mainAppFolder" = "CustomApp"
                    "productId" = "CustomProductId"
                    "customProperty" = "CustomValue"
                }
            } | ConvertTo-Json -Depth 99
            $customComplexSettings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName 'Workflow' -branchName 'dev' -userName 'user' -customSettings $customComplexSettingsJson
            $customComplexSettings.deliverToAppSource.mainAppFolder | Should -Be 'CustomApp'          # Overrides default empty string
            $customComplexSettings.deliverToAppSource.productId | Should -Be 'CustomProductId'        # Overrides default empty string
            $customComplexSettings.deliverToAppSource.customProperty | Should -Be 'CustomValue'       # New property added
            $customComplexSettings.deliverToAppSource.continuousDelivery | Should -Be $false          # Default value preserved (not overridden)

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
            Test-Json -json (ConvertTo-Json $defaultSettings -Depth 99) -schema $schema | Should -Be $true
        }

        It 'Shell setting can only be pwsh or powershell' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            $defaultSettings = GetDefaultSettings
            $defaultSettings.shell = 42
            try {
                Test-Json -json (ConvertTo-Json $defaultSettings -Depth 99) -schema $schema
            }
            catch {
                $_.Exception.Message | Should -Be "The JSON is not valid with the schema: Value is `"integer`" but should be `"string`" at '/shell'"
            }

            $defaultSettings.shell = "random"
            try {
                Test-Json -json (ConvertTo-Json $defaultSettings -Depth 99) -schema $schema
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
                Test-Json -json (ConvertTo-Json $defaultSettings -Depth 99) -schema $schema
            }
            catch {
                $_.Exception.Message | Should -Be "The JSON is not valid with the schema: Value is `"string`" but should be `"array`" at '/projects'"
            }

            # If the projects setting is an array, but contains non-string values, it should throw an error
            $defaultSettings.projects = @("project1", 42)
            try {
                Test-Json -json (ConvertTo-Json $defaultSettings -Depth 99) -schema $schema
            }
            catch {
                $_.Exception.Message | Should -Be "The JSON is not valid with the schema: Value is `"integer`" but should be `"string`" at '/projects/1'"
            }

            # If the projects setting is an array of strings, it should pass the schema validation
            $defaultSettings.projects = @("project1")
            Test-Json -json (ConvertTo-Json $defaultSettings -Depth 99) -schema $schema | Should -Be $true
            $defaultSettings.projects = @("project1", "project2")
            Test-Json -json (ConvertTo-Json $defaultSettings -Depth 99) -schema $schema | Should -Be $true
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

        It 'Multiple conditionalSettings with same array setting are merged (all entries kept)' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            New-Item $githubFolder -ItemType Directory | Out-Null

            # Create conditional settings with two blocks that both match and both have workflowDefaultInputs
            $conditionalSettings = [ordered]@{
                "conditionalSettings" = @(
                    @{
                        "branches" = @( 'main' )
                        "settings" = @{
                            "workflowDefaultInputs" = @(
                                @{ "name" = "input1"; "value" = "value1" }
                            )
                        }
                    }
                    @{
                        "branches" = @( 'main' )
                        "settings" = @{
                            "workflowDefaultInputs" = @(
                                @{ "name" = "input1"; "value" = "value2" },
                                @{ "name" = "input2"; "value" = "value3" }
                            )
                        }
                    }
                )
            }
            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = $conditionalSettings | ConvertTo-Json -Depth 99

            # Both conditional blocks match branch 'main', so both should be applied
            $settings = ReadSettings -baseFolder $tempName -project '' -repoName 'repo' -workflowName 'Workflow' -branchName 'main' -userName 'user'

            # Verify array was merged - should have 3 entries total
            $settings.workflowDefaultInputs | Should -Not -BeNullOrEmpty
            $settings.workflowDefaultInputs.Count | Should -Be 3

            # First entry from first conditional block
            $settings.workflowDefaultInputs[0].name | Should -Be 'input1'
            $settings.workflowDefaultInputs[0].value | Should -Be 'value1'

            # Second entry from second conditional block
            $settings.workflowDefaultInputs[1].name | Should -Be 'input1'
            $settings.workflowDefaultInputs[1].value | Should -Be 'value2'

            # Third entry from second conditional block
            $settings.workflowDefaultInputs[2].name | Should -Be 'input2'
            $settings.workflowDefaultInputs[2].value | Should -Be 'value3'

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'Protection from an earlier source prevents a later override' {
            Mock Write-Host { }
            Mock Out-Host { }
            Mock OutputNotice { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Repo settings: protected settings includes "country", set country = "de"
            @{ "protectedSettings" = @("country"); "country" = "de" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -Encoding utf8 -Force

            # Project settings: try to override country = "ch"
            @{ "country" = "ch" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            # Protected setting from repo should prevent project from overwriting
            $metadata = @{}
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName '' -metadata $metadata
            $settings.country | Should -Be 'de'   # Repo protected value wins
            $settings.Contains('protectedSettings') | Should -BeFalse
            Should -Invoke OutputNotice -Times 0 -Exactly
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.country.sourcesSkipped[0].source | Should -Match '^settings .*Project.*settings\.json \(File\)$'
            $metadata.properties.country.sourcesSkipped[0].reason | Should -Match '^protected by settings \.github.*\(File\)$'

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'Multiple protectedSettings are respected' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Repo settings: mark both country and keyVaultName as protected
            @{
                "protectedSettings" = @("country", "keyVaultName")
                "country"           = "de"
                "keyVaultName"      = "orgVault"
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -Encoding utf8 -Force

            # Project settings: try to override both
            @{
                "country"      = "ch"
                "keyVaultName" = "projectVault"
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            $metadata = @{}
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName '' -metadata $metadata
            $settings.country | Should -Be 'de'
            $settings.keyVaultName | Should -Be 'orgVault'
            $settings.Contains('protectedSettings') | Should -BeFalse
            foreach ($prop in @('country', 'keyVaultName')) {
                $metadata.properties[$prop].sourcesSkipped.Count | Should -Be 1
                $metadata.properties[$prop].sourcesSkipped[0].source | Should -Match '^settings .*Project.*settings\.json \(File\)$'
                $metadata.properties[$prop].sourcesSkipped[0].reason | Should -Match '^protected by settings \.github.*\(File\)$'
            }

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'Later protected settings can override earlier protected settings' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Org settings (via variable): mark country as protected and set to "de"
            $ENV:ALGoOrgSettings = @{
                "protectedSettings" = @("country")
                "country"           = "de"
            } | ConvertTo-Json -Depth 99

            # Repo settings: try to override country with normal (non-protected) setting = "us"
            @{ "country" = "us" } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -Encoding utf8 -Force

            # Project settings: try to override with protected setting = "ch"
            @{
                "protectedSettings" = @("country")
                "country"           = "ch"
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            # Project setting is also marked as protected and should be allowed to override
            # a protected setting from an earlier source.
            $metadata = @{}
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName '' -metadata $metadata
            $settings.country | Should -Be 'ch'   # Source protected overrides destination protected
            $metadata.properties.country.sources | Should -Match '^settings .*Project.*settings\.json \(File\)$'
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.country.sourcesSkipped[0].source | Should -Match '^settings \.github.*\(File\)$'
            $metadata.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings ALGoOrgSettings (Variable)'

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'Logs unknown when a protected setting has no source metadata' {
            foreach ($case in @('missing', 'empty')) {
                $dst = [ordered]@{ country = 'de' }
                $propertyMetadata = @{ protected = $true }
                if ($case -eq 'empty') {
                    $propertyMetadata.sources = @()
                }
                $metadata = @{ properties = @{ country = $propertyMetadata } }

                MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ country = 'ch' }) -context 'settings Test' -metadata $metadata

                $dst.country | Should -Be 'de'
                $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
                $metadata.properties.country.sourcesSkipped[0].source | Should -Be 'settings Test'
                $metadata.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by unknown'
            }
        }

        It 'Collects repeated skipped sources without reporting them during resolution' {
            Mock OutputNotice { }

            $dst = [ordered]@{ country = 'de' }
            $metadata = @{ properties = @{ country = @{ protected = $true; sources = @('settings Organization') } } }
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ country = 'first-secret' }) -context 'settings Repository' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ country = 'second-secret'; overwriteSettings = @('country') }) -context 'settings Project' -metadata $metadata

            $dst.country | Should -Be 'de'
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 2
            $metadata.properties.country.sourcesSkipped[0].source | Should -Be 'settings Repository'
            $metadata.properties.country.sourcesSkipped[1].source | Should -Be 'settings Project'
            $metadata.properties.country.sourcesSkipped[1].reason | Should -Be 'protected by settings Organization'
            Should -Invoke OutputNotice -Times 0 -Exactly
        }

        It 'Populates optional metadata for each read without printing a source group' {
            Mock OutputGroupStart { }
            Mock OutputGroupEnd { }

            $metadata = @{ stale = $true }
            $settings = ReadSettings -baseFolder $PSScriptRoot -project '' -repoName 'repo' -workflowName '' -orgSettingsVariableValue '{"country":"de"}' -repoSettingsVariableValue '' -environmentSettingsVariableValue '' -metadata $metadata
            $settings.country | Should -Be 'de'
            $metadata.ContainsKey('stale') | Should -BeFalse
            $metadata.properties.country.sources | Should -Be @('settings ALGoOrgSettings (Variable)')

            $settings = ReadSettings -baseFolder $PSScriptRoot -project '' -repoName 'repo' -workflowName '' -orgSettingsVariableValue '' -repoSettingsVariableValue '' -environmentSettingsVariableValue '' -metadata $metadata
            $settings.country | Should -Be 'us'
            $metadata.properties.ContainsKey('country') | Should -BeFalse
            Should -Invoke OutputGroupStart -Times 0 -Exactly
            Should -Invoke OutputGroupEnd -Times 0 -Exactly
        }

        It 'Records accepted and derived sources in metadata' {
            $metadata = @{}
            $settings = ReadSettings -baseFolder $PSScriptRoot -project '' -repoName 'repo' -workflowName '' -orgSettingsVariableValue '{"additionalCountries":["de"],"workspaceCompilation":{"parallelism":0}}' -repoSettingsVariableValue '' -environmentSettingsVariableValue '' -customSettings '{"additionalCountries":["at"]}' -metadata $metadata

            $settings.additionalCountries | Should -Be @('de', 'at')
            $metadata.properties.additionalCountries.sources | Should -Be @('default', 'settings ALGoOrgSettings (Variable)', 'settings CustomSettings (Parameter)')
            $metadata.properties.workspaceCompilation.sources | Should -Be @('default', 'settings ALGoOrgSettings (Variable)')
            $metadata.properties.workspaceCompilation.properties.parallelism.sources | Should -Be @('derived from processor count')
            $metadata.properties.shell.sources | Should -Be @('derived from runs-on')
            $metadata.properties.ContainsKey('country') | Should -BeFalse
        }

        It 'Keeps default sources for extensions and clears them for accepted overwrites' {
            $dst = [ordered]@{
                country = 'us'
                projects = @('default-project')
                nested = [ordered]@{ items = @('default-item') }
            }
            $metadata = @{}

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                country = 'de'
                projects = @('first-project')
                nested = [PSCustomObject]@{ items = @('first-item') }
                newList = @('first-new')
            }) -context 'settings First' -metadata $metadata

            $metadata.properties.country.sources | Should -Be @('settings First')
            $metadata.properties.projects.sources | Should -Be @('default', 'settings First')
            $metadata.properties.nested.sources | Should -Be @('default', 'settings First')
            $metadata.properties.nested.properties.items.sources | Should -Be @('default', 'settings First > nested')
            $metadata.properties.newList.sources | Should -Be @('settings First')

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                overwriteSettings = @('projects')
                projects = @('replacement-project')
                nested = [PSCustomObject]@{ overwriteSettings = @('items'); items = @('replacement-item') }
            }) -context 'settings Second' -metadata $metadata

            $dst.projects | Should -Be @('replacement-project')
            $dst.nested.items | Should -Be @('replacement-item')
            $metadata.properties.projects.sources | Should -Be @('settings Second')
            $metadata.properties.nested.sources | Should -Be @('default', 'settings First', 'settings Second')
            $metadata.properties.nested.properties.items.sources | Should -Be @('settings Second > nested')
        }

        It 'Does not log a skip when the source also protects the setting' {
            $dst = [ordered]@{ country = 'de' }
            $metadata = @{ properties = @{ country = @{ protected = $true; sources = @('settings Original') } } }
            $src = [PSCustomObject]@{ protectedSettings = @('country'); country = 'ch' }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src -context 'settings Test' -metadata $metadata

            $dst.country | Should -Be 'ch'
            $metadata.properties.country.protected | Should -BeTrue
            $metadata.properties.country.sources | Should -Be @('settings Test')
            $metadata.properties.country.ContainsKey('sourcesSkipped') | Should -BeFalse
        }

        It 'Logs the nested context when a protected setting is skipped' {
            $dst = [ordered]@{
                custom = [ordered]@{ country = 'de' }
            }
            $metadata = @{ properties = @{ custom = @{ properties = @{ country = @{ protected = $true; sources = @('settings Original') } } } } }
            $src = [PSCustomObject]@{
                custom = [PSCustomObject]@{ country = 'ch' }
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src -context 'settings Test' -metadata $metadata

            $dst.custom.country | Should -Be 'de'
            $metadata.properties.custom.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.custom.properties.country.sourcesSkipped[0].source | Should -Be 'settings Test > custom'
            $metadata.properties.custom.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings Original'
        }

        It 'Tracks the source of a nested protected setting across merges' {
            $dst = [ordered]@{ custom = [ordered]@{ country = 'us' } }
            $metadata = @{}
            $firstSource = [PSCustomObject]@{
                custom = [PSCustomObject]@{ protectedSettings = @('country'); country = 'de' }
            }
            $laterSource = [PSCustomObject]@{
                custom = [PSCustomObject]@{ country = 'ch' }
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $firstSource -context 'settings Organization' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $laterSource -context 'settings Project' -metadata $metadata

            $dst.custom.country | Should -Be 'de'
            $dst.custom.Contains('protectedSettings') | Should -BeFalse
            $metadata.properties.custom.properties.country.protected | Should -BeTrue
            $metadata.properties.custom.properties.country.sources | Should -Be @('settings Organization > custom')
            $metadata.properties.custom.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.custom.properties.country.sourcesSkipped[0].source | Should -Be 'settings Project > custom'
            $metadata.properties.custom.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings Organization > custom'
        }

        It 'Keeps nested protection separate for sibling objects' {
            $dst = [ordered]@{
                first = [ordered]@{ country = 'us' }
                second = [ordered]@{ country = 'us' }
            }
            $metadata = @{}
            $firstSource = [PSCustomObject]@{
                first = [PSCustomObject]@{ protectedSettings = @('country'); country = 'de' }
            }
            $laterSource = [PSCustomObject]@{
                first = [PSCustomObject]@{ country = 'ch' }
                second = [PSCustomObject]@{ country = 'at' }
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $firstSource -context 'settings Organization' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $laterSource -context 'settings Project' -metadata $metadata

            $dst.first.country | Should -Be 'de'
            $dst.second.country | Should -Be 'at'
            $metadata.properties.second.properties.country.Contains('protected') | Should -BeFalse
            $metadata.properties.second.properties.country.ContainsKey('sourcesSkipped') | Should -BeFalse
            $metadata.properties.first.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.first.properties.country.sourcesSkipped[0].source | Should -Be 'settings Project > first'
            $metadata.properties.first.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings Organization > first'
        }

        It 'Retains the protecting source when a later declaration supplies no value' {
            $dst = [ordered]@{ country = 'us' }
            $metadata = @{}
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ protectedSettings = @('country'); country = 'de' }) -context 'settings Organization' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ protectedSettings = @('country') }) -context 'settings Repository' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ country = 'ch' }) -context 'settings Project' -metadata $metadata

            $dst.country | Should -Be 'de'
            $metadata.properties.country.protected | Should -BeTrue
            $metadata.properties.country.sources | Should -Be @('settings Organization')
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.country.sourcesSkipped[0].source | Should -Be 'settings Project'
            $metadata.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings Organization'
        }

        It 'Ignores protection declared without a value' {
            $dst = [ordered]@{}
            $metadata = @{}
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ protectedSettings = @('futureSetting') }) -context 'settings Organization' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{ futureSetting = 'later' }) -context 'settings Project' -metadata $metadata

            $dst.futureSetting | Should -Be 'later'
            $metadata.Contains('properties') | Should -BeTrue
            $metadata.properties.futureSetting.Contains('protected') | Should -BeFalse
            $metadata.properties.futureSetting.Contains('properties') | Should -BeFalse
            $metadata.properties.futureSetting.ContainsKey('sourcesSkipped') | Should -BeFalse
        }

        It 'Replacing an unprotected parent discards its nested protections' {
            $dst = [ordered]@{ alDoc = [ordered]@{ includeProjects = @('default') } }
            $metadata = @{}
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                alDoc = [PSCustomObject]@{ protectedSettings = @('includeProjects'); includeProjects = @('org') }
            }) -context 'settings Organization' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                overwriteSettings = @('alDoc')
                alDoc = [PSCustomObject]@{ includeProjects = @('repo') }
            }) -context 'settings Repository' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                alDoc = [PSCustomObject]@{ includeProjects = @('project') }
            }) -context 'settings Project' -metadata $metadata

            $dst.alDoc.includeProjects | Should -Be @('repo', 'project')
            $metadata.properties.alDoc.properties.includeProjects.Contains('protected') | Should -BeFalse
            $metadata.properties.alDoc.properties.includeProjects.ContainsKey('sourcesSkipped') | Should -BeFalse
        }

        It 'Requires nested protection to overwrite a protected array' {
            $dst = [ordered]@{ alDoc = [ordered]@{ includeProjects = @('org') } }
            $metadata = @{}
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                alDoc = [PSCustomObject]@{ protectedSettings = @('includeProjects'); includeProjects = @('repo') }
            }) -context 'settings Repository' -metadata $metadata
            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                alDoc = [PSCustomObject]@{ overwriteSettings = @('includeProjects'); includeProjects = @('project') }
            }) -context 'settings Project' -metadata $metadata

            $dst.alDoc.includeProjects | Should -Be @('org', 'repo')
            $metadata.properties.alDoc.properties.includeProjects.protected | Should -BeTrue
            $metadata.properties.alDoc.properties.includeProjects.sources | Should -Be @('default', 'settings Repository > alDoc')
            $metadata.properties.alDoc.properties.includeProjects.sourcesSkipped.Count | Should -Be 1

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src ([PSCustomObject]@{
                alDoc = [PSCustomObject]@{ protectedSettings = @('includeProjects'); overwriteSettings = @('includeProjects'); includeProjects = @('workflow') }
            }) -context 'settings Workflow' -metadata $metadata

            $dst.alDoc.includeProjects | Should -Be @('workflow')
            $dst.alDoc.Contains('protectedSettings') | Should -BeFalse
            $metadata.properties.alDoc.properties.includeProjects.protected | Should -BeTrue
            $metadata.properties.alDoc.properties.includeProjects.sources | Should -Be @('settings Workflow > alDoc')
            $metadata.properties.alDoc.properties.includeProjects.ContainsKey('sourcesSkipped') | Should -BeFalse
        }

        It 'Does not merge a protected array without overwriteSettings' {
            $dst = [ordered]@{ additionalCountries = @('de', 'at') }
            $metadata = @{ properties = @{ additionalCountries = @{ protected = $true; sources = @('settings Original') } } }
            $src = [PSCustomObject]@{ additionalCountries = @('ch', 'be') }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src -context 'settings Test' -metadata $metadata

            $dst.additionalCountries | Should -Be @('de', 'at')
            $metadata.properties.additionalCountries.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.additionalCountries.sourcesSkipped[0].source | Should -Be 'settings Test'
            $metadata.properties.additionalCountries.sourcesSkipped[0].reason | Should -Be 'protected by settings Original'
        }

        It 'Does not overwrite protection metadata through overwriteSettings' {
            $dst = [ordered]@{ country = 'de' }
            $metadata = @{ properties = @{ country = @{ protected = $true; sources = @('settings Original') } } }
            $src = [PSCustomObject]@{
                overwriteSettings = @('protectedSettings')
                protectedSettings = @('keyVaultName')
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src -metadata $metadata

            $dst.Contains('protectedSettings') | Should -BeFalse
            $metadata.properties.country.protected | Should -BeTrue
            $metadata.properties.country.sources | Should -Be @('settings Original')
            $metadata.properties.Contains('keyVaultName') | Should -BeFalse
            $dst.country | Should -Be 'de'
        }

        It 'Does not let protectedSettings protect itself from processing' {
            $dst = [ordered]@{ country = 'de' }
            $metadata = @{ properties = @{ country = @{ protected = $true; sources = @('settings Original') } } }
            $src = [PSCustomObject]@{
                protectedSettings = @('protectedSettings', 'keyVaultName')
                country = 'ch'
            }

            MergeCustomObjectIntoOrderedDictionary -dst $dst -src $src -context 'settings Test' -metadata $metadata

            $dst.Contains('protectedSettings') | Should -BeFalse
            $metadata.properties.Contains('protectedSettings') | Should -BeFalse
            $metadata.properties.Contains('keyVaultName') | Should -BeFalse
            $dst.country | Should -Be 'de'
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.country.sourcesSkipped[0].source | Should -Be 'settings Test'
            $metadata.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings Original'
        }

        It 'protectedSettings are not overridden by overwriteSettings unless source also marks them protected' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Repo settings: mark additionalCountries as protected
            @{
                "protectedSettings"   = @("additionalCountries")
                "additionalCountries" = @("de", "at")
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -Encoding utf8 -Force

            # Project settings: use overwriteSettings to override additionalCountries (force replacement instead of merge)
            @{
                "overwriteSettings"   = @("additionalCountries")
                "additionalCountries" = @("ch", "be")
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            # Neither overwriteSettings nor the source array should change the protected setting.
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName ''
            $settings.additionalCountries | Should -Be @("de", "at")

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'protectedSettings can be overridden with overwriteSettings when source also marks them protected' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            @{
                "protectedSettings"   = @("additionalCountries")
                "additionalCountries" = @("de", "at")
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -Encoding utf8 -Force

            @{
                "protectedSettings"   = @("additionalCountries")
                "overwriteSettings"   = @("additionalCountries")
                "additionalCountries" = @("ch", "be")
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName ''
            $settings.additionalCountries | Should -Be @("ch", "be")

            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'Empty protectedSettings has no effect (backward compatibility)' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Repo settings: protectedSettings is empty
            @{
                "protectedSettings" = @()
                "country"           = "us"
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -Encoding utf8 -Force

            # Project settings: override country
            @{
                "country" = "ch"
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            # Without protected marking, normal hierarchy applies
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName ''
            $settings.country | Should -Be 'ch'   # Project wins (normal behavior)
            $settings.Contains('protectedSettings') | Should -BeFalse

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'ConditionalSetting with protectedSettings at repo level overrides project setting for specific buildMode' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Repo settings: ConditionalSetting for buildMode "ValidateUS" with protected country marking
            @{
                "ConditionalSettings" = @(
                    @{
                        "buildModes" = @("ValidateUS")
                        "settings"   = @{
                            "protectedSettings" = @("country")   # Mark country as protected
                            "country"           = "us"
                        }
                    }
                )
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $githubFolder "AL-Go-Settings.json") -Encoding utf8 -Force

            # Project settings: country = "w1", buildModes include "ValidateUS"
            @{
                "country"    = "w1"
                "buildModes" = @("Default", "ValidateUS")
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            $ENV:ALGoOrgSettings = ''
            $ENV:ALGoRepoSettings = ''

            # When reading for buildMode "Default", project country "w1" should be used
            $defaultMetadata = @{}
            $settingsDefault = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -buildMode 'Default' -userName '' -metadata $defaultMetadata
            $settingsDefault.country | Should -Be 'w1'   # No org conditional applies for "Default"
            $defaultMetadata.properties.country.ContainsKey('sourcesSkipped') | Should -BeFalse

            # When reading for buildMode "ValidateUS", repo conditional with protected marking should override project
            $metadata = @{}
            $settingsValidateUS = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -buildMode 'ValidateUS' -userName '' -metadata $metadata
            $settingsValidateUS.country | Should -Be 'us'   # Repo conditional protected setting wins
            $settingsValidateUS.buildModes | Should -Contain 'ValidateUS'
            $settingsValidateUS.Contains('protectedSettings') | Should -BeFalse
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.country.sourcesSkipped[0].source | Should -Match '^settings .*Project.*settings\.json \(File\)$'
            $metadata.properties.country.sourcesSkipped[0].reason | Should -Match '^protected by settings \.github.*conditional settings for buildModes: ValidateUS$'

            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }

        It 'Logs the conditions when a protected setting is skipped by conditional settings' {
            $orgSettings = @{ protectedSettings = @('country'); country = 'de' } | ConvertTo-Json -Depth 99
            $repoSettings = @{
                ConditionalSettings = @(
                    @{ buildModes = @('ValidateUS'); settings = @{ country = 'ch' } }
                )
            } | ConvertTo-Json -Depth 99

            $metadata = @{}
            $settings = ReadSettings -baseFolder $PSScriptRoot -project '' -repoName 'repo' -workflowName '' -branchName '' -buildMode 'ValidateUS' -userName '' -orgSettingsVariableValue $orgSettings -repoSettingsVariableValue $repoSettings -metadata $metadata

            $settings.country | Should -Be 'de'
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.country.sourcesSkipped[0].source | Should -Be 'settings ALGoRepoSettings (Variable) > conditional settings for buildModes: ValidateUS'
            $metadata.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings ALGoOrgSettings (Variable)'
        }

        It 'Applies protection to customSettings unless it also protects the setting' {
            $orgSettings = @{ protectedSettings = @('country'); country = 'de' } | ConvertTo-Json -Depth 99
            $customSettings = @{ country = 'ch'; companyName = 'Custom' } | ConvertTo-Json -Depth 99

            $metadata = @{}
            $settings = ReadSettings -baseFolder $PSScriptRoot -project '' -repoName 'repo' -workflowName '' -branchName '' -userName '' -orgSettingsVariableValue $orgSettings -repoSettingsVariableValue '' -environmentSettingsVariableValue '' -customSettings $customSettings -metadata $metadata

            $settings.country | Should -Be 'de'
            $settings.companyName | Should -Be 'Custom'
            $metadata.properties.country.sourcesSkipped.Count | Should -Be 1
            $metadata.properties.country.sourcesSkipped[0].source | Should -Be 'settings CustomSettings (Parameter)'
            $metadata.properties.country.sourcesSkipped[0].reason | Should -Be 'protected by settings ALGoOrgSettings (Variable)'

            $customSettings = @{ protectedSettings = @('country'); country = 'ch' } | ConvertTo-Json -Depth 99
            $metadata = @{}
            $settings = ReadSettings -baseFolder $PSScriptRoot -project '' -repoName 'repo' -workflowName '' -branchName '' -userName '' -orgSettingsVariableValue $orgSettings -repoSettingsVariableValue '' -environmentSettingsVariableValue '' -customSettings $customSettings -metadata $metadata

            $settings.country | Should -Be 'ch'
            $metadata.properties.country.ContainsKey('sourcesSkipped') | Should -BeFalse
        }

        It 'protectedSettings are merged correctly' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Org settings: protectedSettings is filled
            $orgSettings = @{
                "protectedSettings" = @("country")
                "country"           = "us"
            } | ConvertTo-Json -Depth 99

            # Repo settings: add another protected setting
            $repoSettings = @{
                "protectedSettings" = @("companyName")
                "country"           = "de"
                "companyName"       = "MyCompany"
            } | ConvertTo-Json -Depth 99

            # Project settings: add another protected setting
            @{
                "protectedSettings" = @("keyVaultName")
                "country"           = "ch"
                "keyVaultName"      = "mykv"
                "companyName"       = "AnotherCompany"
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            # Without protected marking, normal hierarchy applies
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName '' -orgSettingsVariableValue $orgSettings -repoSettingsVariableValue $repoSettings
            $settings.Contains('protectedSettings') | Should -BeFalse

            $settings.country | Should -Be 'us'   # from org settings
            $settings.companyName | Should -Be 'MyCompany'   # from repo settings
            $settings.keyVaultName | Should -Be 'mykv'   # from project settings


            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }
        It 'conditional protectedSettings are merged correctly' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Org settings: protectedSettings is filled
            $orgSettings = @{
                "ConditionalSettings" = @(
                    @{
                        "buildModes" = @("CustomBuildMode")
                        "settings"   = @{
                            "protectedSettings" = @("country")
                            "country"           = "us"
                        }
                    })
            } | ConvertTo-Json -Depth 99

            # Repo settings: add another protected setting
            $repoSettings = @{
                "ConditionalSettings" = @(
                    @{
                        "buildModes" = @("CustomBuildMode")
                        "settings"   = @{   "protectedSettings" = @("companyName")
                            "country"                         = "de"
                            "companyName"                     = "MyCompany"
                        }
                    })
            } | ConvertTo-Json -Depth 99

            # Project settings: add another protected setting
            @{
                "ConditionalSettings" = @(
                    @{
                        "buildModes" = @("CustomBuildMode")
                        "settings"   = @{ "protectedSettings" = @("keyVaultName")
                            "country"                       = "ch"
                            "keyVaultName"                  = "mykv"
                            "companyName"                   = "AnotherCompany"
                        }
                    })
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            # Without protected marking, normal hierarchy applies
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName '' -buildMode 'CustomBuildMode' -orgSettingsVariableValue $orgSettings -repoSettingsVariableValue $repoSettings
            $settings.Contains('protectedSettings') | Should -BeFalse

            $settings.country | Should -Be 'us'   # from org settings
            $settings.companyName | Should -Be 'MyCompany'   # from repo settings
            $settings.keyVaultName | Should -Be 'mykv'   # from project settings


            # Clean up
            Pop-Location
            Remove-Item -Path $tempName -Recurse -Force
        }
        It 'mixed protectedSettings are merged correctly' {
            Mock Write-Host { }
            Mock Out-Host { }

            Push-Location
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $githubFolder = Join-Path $tempName ".github"
            $projectALGoFolder = Join-Path $tempName "Project/$ALGoFolderName"

            try {
            New-Item $githubFolder -ItemType Directory | Out-Null
            New-Item $projectALGoFolder -ItemType Directory | Out-Null

            # Org settings: protectedSettings is filled
            $ENV:ALGoOrgSettings = @{
                "ConditionalSettings" = @(
                    @{
                        "buildModes" = @("CustomBuildMode")
                        "settings"   = @{
                            "protectedSettings" = @("country")
                            "country"           = "us"
                        }
                    })
            } | ConvertTo-Json -Depth 99

            # Repo settings: add another protected setting
            $ENV:ALGoRepoSettings = @{
                "protectedSettings" = @("companyName")
                "country"           = "de"
                "companyName"       = "MyCompany"

            } | ConvertTo-Json -Depth 99

            # Project settings: add another protected setting
            @{
                "ConditionalSettings" = @(
                    @{
                        "buildModes" = @("CustomBuildMode")
                        "settings"   = @{ "protectedSettings" = @("keyVaultName")
                            "country"                       = "ch"
                            "keyVaultName"                  = "mykv"
                            "companyName"                   = "AnotherCompany"
                        }
                    })
            } | ConvertTo-Json -Depth 99 |
            Set-Content -Path (Join-Path $projectALGoFolder "settings.json") -Encoding utf8 -Force

            # Without protected marking, normal hierarchy applies
            $settings = ReadSettings -baseFolder $tempName -project 'Project' -repoName 'repo' -workflowName '' -branchName '' -userName '' -buildMode 'CustomBuildMode'
            $settings.Contains('protectedSettings') | Should -BeFalse

            $settings.country | Should -Be 'us'   # from org settings
            $settings.companyName | Should -Be 'MyCompany'   # from repo settings
            $settings.keyVaultName | Should -Be 'mykv'   # from project settings


            }
            finally {
                Pop-Location
                Remove-Item -Path $tempName -Recurse -Force
            }
        }

        It 'ValidateSettings skips validation entirely on PS versions less than 7 without warning' {
            Mock OutputWarning { }
            Mock ConvertTo-Json { '{}' }

            $settings = @{ "someProp" = "someValue" }

            if ($PSVersionTable.PSVersion.Major -ge 7) {
                Mock Test-Json { }
                $settings | ValidateSettings
                # On PS7+, Test-Json is called directly for validation
                Should -Invoke -CommandName Test-Json -Times 1
                Should -Invoke -CommandName ConvertTo-Json -Times 1
            }
            else {
                # On PS < 7, validation is skipped entirely
                $settings | ValidateSettings
                Should -Invoke -CommandName ConvertTo-Json -Times 0
            }

            # Verify no warning was output
            Should -Invoke -CommandName OutputWarning -Times 0
        }
    }

    Describe 'OutputSettingsSources' {
        It 'Prints effective sources, defaults, and nested protection without values' {
            Mock Write-Host { }

            $settings = [ordered]@{
                country = 'secret-value'
                type = 'PTE'
                projects = @('secret-project')
                nested = [ordered]@{ key = 'nested-secret' }
            }
            $metadata = @{ properties = @{
                country = @{ sources = @('Organization'); protected = $true }
                projects = @{ sources = @('default', 'Repository', 'Project') }
                nested = @{ sources = @('default', 'Repository'); properties = @{
                    key = @{ sources = @('default', 'Project'); protected = $true }
                } }
            } }

            OutputSettingsSources -settings $settings -metadata $metadata

            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'country: Organization (protected)' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'type: default' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'projects: default, Repository, Project' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'nested: default, Repository' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'nested.key: default, Project (protected)' }
            Should -Invoke Write-Host -Times 5 -Exactly -ParameterFilter { $Object -notmatch 'secret' }
            Should -Invoke Write-Host -Times 5 -Exactly
        }
    }

    Describe 'OutputSettingsNotices' {
        It 'Prints repeated and nested skips without setting values' {
            Mock OutputNotice { }

            $settings = [ordered]@{
                country = 'secret-country'
                nested = [ordered]@{ key = 'secret-key'; other = 'secret-other' }
            }
            $metadata = @{ properties = @{
                country = @{ sourcesSkipped = @(
                    @{ source = 'Repository'; reason = 'protected by Organization' },
                    @{ source = 'Project'; reason = 'protected by Organization' }
                ) }
                nested = @{ properties = @{
                    key = @{ sourcesSkipped = @(@{ source = 'Workflow > nested'; reason = 'protected by Repository > nested' }) }
                } }
            } }

            OutputSettingsNotices -settings $settings -metadata $metadata

            Should -Invoke OutputNotice -Times 1 -Exactly -ParameterFilter { $message -eq 'Skipped setting country from Repository: protected by Organization' }
            Should -Invoke OutputNotice -Times 1 -Exactly -ParameterFilter { $message -eq 'Skipped setting country from Project: protected by Organization' }
            Should -Invoke OutputNotice -Times 1 -Exactly -ParameterFilter { $message -eq 'Skipped setting nested.key from Workflow > nested: protected by Repository > nested' }
            Should -Invoke OutputNotice -Times 3 -Exactly -ParameterFilter { $message -notmatch 'secret' }
            Should -Invoke OutputNotice -Times 3 -Exactly
        }

        It 'Prints nothing when no source was skipped' {
            Mock OutputNotice { }

            $settings = [ordered]@{ country = 'secret'; nested = [ordered]@{ key = 'secret' } }
            $metadata = @{ properties = @{ country = @{ sources = @('Repository') }; nested = @{ properties = @{ key = @{ sources = @('Project') } } } } }

            OutputSettingsNotices -settings $settings -metadata $metadata

            Should -Invoke OutputNotice -Times 0 -Exactly
        }
    }
}
