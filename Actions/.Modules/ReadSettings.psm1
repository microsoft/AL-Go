Import-Module (Join-Path -Path $PSScriptRoot "DebugLogHelper.psm1")

$ALGoFolderName = '.AL-Go'
$ALGoSettingsFileName = 'settings.json'
$ALGoSettingsFile = Join-Path '.AL-Go' $ALGoSettingsFileName

$RepoSettingsFileName = 'AL-Go-Settings.json'
$RepoSettingsFile = Join-Path '.github' $RepoSettingsFileName

$CustomTemplateRepoSettingsFileName = 'AL-Go-TemplateRepoSettings.doNotEdit.json'
$CustomTemplateRepoSettingsFile = Join-Path '.github' $CustomTemplateRepoSettingsFileName

$CustomTemplateProjectSettingsFileName = 'AL-Go-TemplateProjectSettings.doNotEdit.json'
$CustomTemplateProjectSettingsFile = Join-Path '.github' $CustomTemplateProjectSettingsFileName

function MergeCustomObjectIntoOrderedDictionary {
    Param(
        [System.Collections.Specialized.OrderedDictionary] $dst,
        [PSCustomObject] $src
    )

    # If the src object contains property 'overwriteSettings' (list of settings), remove these settings from the dst object, so that they can be re-added with the new value later on
    if ($src.PSObject.Properties.Name -contains "overwriteSettings") {
        $src.overwriteSettings | ForEach-Object {
            $prop = $_
            if ($dst.Contains($prop) -and $src.PSObject.Properties.Name -contains $prop) {
                # Remove the property from the destination object only if it also exists in the source object. The property will be re-added with the new value later on.
                OutputDebug "Overwriting setting $prop"
                $dst.Remove($prop)
            }
        }
    }

    # Loop through all properties in the source object
    # If the property does not exist in the destination object, add it with the right type, but no value
    # Types supported: PSCustomObject, Object[] and simple types
    $src.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $prop = $_.Name

        # Skip overwriteSettings property as it's only used to remove settings from the destination object and is specific to the source object
        if ($prop -eq "overwriteSettings") {
            return
        }

        $srcProp = $src."$prop"
        $srcPropType = $srcProp.GetType().Name
        if (-not $dst.Contains($prop)) {
            if ($srcPropType -eq "PSCustomObject") {
                $dst.Add("$prop", [ordered]@{})
            }
            elseif ($srcPropType -eq "Object[]") {
                $dst.Add("$prop", @())
            }
            else {
                $dst.Add("$prop", $srcProp)
            }
        }
    }

    # Loop through all properties in the destination object
    # If the property does not exist in the source object, do nothing
    # If the property exists in the source object, but is of a different type, throw an error
    # If the property exists in the source object:
    # If the property is an Object, call this function recursively to merge values
    # If the property is an Object[], merge the arrays
    # If the property is a simple type, replace the value in the destination object with the value from the source object
    @($dst.Keys) | ForEach-Object {
        $prop = $_
        if ($src.PSObject.Properties.Name -eq $prop) {
            $dstProp = $dst."$prop"
            $srcProp = $src."$prop"
            $dstPropType = $dstProp.GetType().Name
            $srcPropType = $srcProp.GetType().Name
            if ($srcPropType -eq "PSCustomObject" -and $dstPropType -eq "OrderedDictionary") {
                MergeCustomObjectIntoOrderedDictionary -dst $dst."$prop" -src $srcProp
            }
            elseif ($dstPropType -ne $srcPropType -and !($srcPropType -eq "Int64" -and $dstPropType -eq "Int32")) {
                # Under Linux, the Int fields read from the .json file will be Int64, while the settings defaults will be Int32
                # This is not seen as an error and will not throw an error
                throw "property $prop should be of type $dstPropType, is $srcPropType."
            }
            else {
                if ($srcProp -is [Object[]]) {
                    $srcProp | ForEach-Object {
                        $srcElm = $_
                        $srcElmType = $srcElm.GetType().Name
                        if ($srcElmType -eq "PSCustomObject") {
                            # Array of objects are not checked for uniqueness
                            $ht = [ordered]@{}
                            $srcElm.PSObject.Properties | Sort-Object -Property Name -Culture ([cultureinfo]::InvariantCulture) | ForEach-Object {
                                $ht[$_.Name] = $_.Value
                            }
                            $dst."$prop" += @($ht)
                        }
                        else {
                            # Add source element to destination array, but only if it does not already exist
                            $dst."$prop" = @($dst."$prop" + $srcElm | Select-Object -Unique)
                        }
                    }
                }
                else {
                    $dst."$prop" = $srcProp
                }
            }
        }
    }
}

function GetDefaultSettings
(
    [string] $repoName
)
{
    return [ordered]@{
        "type"                                          = "PTE"
        "unusedALGoSystemFiles"                         = @()
        "projects"                                      = @()
        "powerPlatformSolutionFolder"                   = ""
        "country"                                       = "us"
        "artifact"                                      = ""
        "companyName"                                   = ""
        "repoVersion"                                   = "1.0"
        "repoName"                                      = "$repoName"
        "versioningStrategy"                            = 0
        "runNumberOffset"                               = 0
        "appBuild"                                      = 0
        "appRevision"                                   = 0
        "keyVaultName"                                  = ""
        "licenseFileUrlSecretName"                      = "licenseFileUrl"
        "ghTokenWorkflowSecretName"                     = "ghTokenWorkflow"
        "adminCenterApiCredentialsSecretName"           = "adminCenterApiCredentials"
        "applicationInsightsConnectionStringSecretName" = "applicationInsightsConnectionString"
        "keyVaultCertificateUrlSecretName"              = "keyVaultCertificateUrl"
        "keyVaultCertificatePasswordSecretName"         = "keyVaultCertificatePassword"
        "keyVaultClientIdSecretName"                    = "keyVaultClientId"
        "keyVaultCodesignCertificateName"               = ""
        "codeSignCertificateUrlSecretName"              = "codeSignCertificateUrl"
        "codeSignCertificatePasswordSecretName"         = "codeSignCertificatePassword"
        "additionalCountries"                           = @()
        "appDependencies"                               = @()
        "projectName"                                   = ""
        "appFolders"                                    = @()
        "testDependencies"                              = @()
        "testFolders"                                   = @()
        "bcptTestFolders"                               = @()
        "pageScriptingTests"                            = @()
        "restoreDatabases"                              = @()
        "installApps"                                   = @()
        "installTestApps"                               = @()
        "installOnlyReferencedApps"                     = $true
        "runTestsInAllInstalledTestApps"                = $false
        "generateDependencyArtifact"                    = $false
        "skipUpgrade"                                   = $false
        "applicationDependency"                         = "18.0.0.0"
        "updateDependencies"                            = $false
        "installTestRunner"                             = $false
        "installTestFramework"                          = $false
        "installTestLibraries"                          = $false
        "installPerformanceToolkit"                     = $false
        "enableCodeCop"                                 = $false
        "enableUICop"                                   = $false
        "enableCodeAnalyzersOnTestApps"                 = $false
        "customCodeCops"                                = @()
        "trackALAlertsInGitHub"                         = $false
        "failOn"                                        = "error"
        "treatTestFailuresAsWarnings"                   = $false
        "rulesetFile"                                   = ""
        "enableExternalRulesets"                        = $false
        "vsixFile"                                      = ""
        "assignPremiumPlan"                             = $false
        "enableTaskScheduler"                           = $false
        "doNotBuildTests"                               = $false
        "doNotRunTests"                                 = $false
        "doNotRunBcptTests"                             = $false
        "doNotRunPageScriptingTests"                    = $false
        "doNotPublishApps"                              = $false
        "doNotSignApps"                                 = $false
        "configPackages"                                = @()
        "appSourceCopMandatoryAffixes"                  = @()
        "deliverToAppSource"                            = [ordered]@{
            "mainAppFolder"                             = ""
            "productId"                                 = ""
            "includeDependencies"                       = @()
            "continuousDelivery"                        = $false
        }
        "obsoleteTagMinAllowedMajorMinor"               = ""
        "memoryLimit"                                   = ""
        "templateUrl"                                   = ""
        "templateSha"                                   = ""
        "templateBranch"                                = ""
        "appDependencyProbingPaths"                     = @()
        "useProjectDependencies"                        = $false
        "runs-on"                                       = "windows-latest"
        "shell"                                         = ""
        "githubRunner"                                  = ""
        "githubRunnerShell"                             = ""
        "cacheImageName"                                = "my"
        "cacheKeepDays"                                 = 3
        "alwaysBuildAllProjects"                        = $false
        "incrementalBuilds"                             = [ordered]@{
            "onPush"                                    = $false
            "onPull_Request"                            = $true
            "onSchedule"                                = $false
            "retentionDays"                             = 30
            "mode"                                      = "modifiedApps" # modifiedProjects, modifiedApps
        }
        "microsoftTelemetryConnectionString"            = "InstrumentationKey=cd2cc63e-0f37-4968-b99a-532411a314b8;IngestionEndpoint=https://northeurope-2.in.applicationinsights.azure.com/"
        "partnerTelemetryConnectionString"              = ""
        "sendExtendedTelemetryToMicrosoft"              = $false
        "environments"                                  = @()
        "buildModes"                                    = @()
        "useCompilerFolder"                             = $false
        "pullRequestTrigger"                            = "pull_request_target"
        "bcptThresholds"                                = [ordered]@{
            "DurationWarning"                           = 10
            "DurationError"                             = 25
            "NumberOfSqlStmtsWarning"                   = 5
            "NumberOfSqlStmtsError"                     = 10
        }
        "fullBuildPatterns"                             = @()
        "excludeEnvironments"                           = @()
        "alDoc"                                         = [ordered]@{
            "continuousDeployment"                      = $false
            "deployToGitHubPages"                       = $true
            "maxReleases"                               = 3
            "groupByProject"                            = $true
            "includeProjects"                           = @()
            "excludeProjects"                           = @()
            "header"                                    = "Documentation for {REPOSITORY} {VERSION}"
            "footer"                                    = "Documentation for <a href=""https://github.com/{REPOSITORY}"">{REPOSITORY}</a> made with <a href=""https://aka.ms/AL-Go"">AL-Go for GitHub</a>, <a href=""https://go.microsoft.com/fwlink/?linkid=2247728"">ALDoc</a> and <a href=""https://dotnet.github.io/docfx"">DocFx</a>"
            "defaultIndexMD"                            = "## Reference documentation\n\nThis is the generated reference documentation for [{REPOSITORY}](https://github.com/{REPOSITORY}).\n\nYou can use the navigation bar at the top and the table of contents to the left to navigate your documentation.\n\nYou can change this content by creating/editing the **{INDEXTEMPLATERELATIVEPATH}** file in your repository or use the alDoc:defaultIndexMD setting in your repository settings file (.github/AL-Go-Settings.json)\n\n{RELEASENOTES}"
            "defaultReleaseMD"                          = "## Release reference documentation\n\nThis is the generated reference documentation for [{REPOSITORY}](https://github.com/{REPOSITORY}).\n\nYou can use the navigation bar at the top and the table of contents to the left to navigate your documentation.\n\nYou can change this content by creating/editing the **{INDEXTEMPLATERELATIVEPATH}** file in your repository or use the alDoc:defaultReleaseMD setting in your repository settings file (.github/AL-Go-Settings.json)\n\n{RELEASENOTES}"
        }
        "trustMicrosoftNuGetFeeds"                      = $true
        "nuGetFeedSelectMode"                           = "LatestMatching"
        "commitOptions"                                 = [ordered]@{
            "messageSuffix"                             = ""
            "pullRequestAutoMerge"                      = $false
            "pullRequestMergeMethod"                    = "squash"
            "pullRequestLabels"                         = @()
            "createPullRequest"                         = $true
        }
        "trustedSigning"                                = [ordered]@{
            "Endpoint"                                  = ""
            "Account"                                   = ""
            "CertificateProfile"                        = ""
        }
        "useGitSubmodules"                              = "false"
        "gitSubmodulesTokenSecretName"                  = "gitSubmodulesToken"
        "shortLivedArtifactsRetentionDays"              = 1  # 0 means use GitHub default
        "reportSuppressedDiagnostics"                   = $false
        "workflowDefaultInputs"                         = @()
        "customALGoFiles" = [ordered]@{
            "filesToInclude"                             = @()
            "filesToExclude"                            = @()
        }
    }
}


<#
    .SYNOPSIS
        Read settings from the settings files and merge them into an ordered dictionary, with optional custom settings override.
    .DESCRIPTION
        This function reads settings from various files and merges them into an ordered dictionary.
        The settings are read from the following files (in order of precedence):
        - ALGoOrgSettings (github Variable)                    = Organization settings variable
        - .github/AL-Go-TemplateRepoSettings.doNotEdit.json    = Repository settings from custom template
        - .github/AL-Go-Settings.json                          = Repository Settings file
        - ALGoRepoSettings (github Variable)                   = Repository settings variable
        - .github/AL-Go-TemplateProjectSettings.doNotEdit.json = Project settings from custom template
        - <project>/.AL-Go/settings.json                       = Project settings file
        - .github/<workflowName>.settings.json                 = Workflow settings file
        - <project>/.AL-Go/<workflowName>.settings.json        = Project workflow settings file
        - <project>/.AL-Go/<userName>.settings.json            = User settings file
        - ALGoEnvSettings (github Variable)                    = Deployment Environment settings variable
        - customSettings parameter (JSON string)               = Custom settings with highest precedence
    .PARAMETER baseFolder
        The base folder where the settings files are located. Default is $ENV:GITHUB_WORKSPACE when running in GitHub Actions.
    .PARAMETER repoName
        The name of the repository. Default is $ENV:GITHUB_REPOSITORY when running in GitHub Actions.
    .PARAMETER project
        The project path relative to the base folder. Default is '.'
    .PARAMETER buildMode
        The build mode to use when there are conditional settings. Default is "Default".
    .PARAMETER workflowName
        The name of the workflow. Default is $ENV:GITHUB_WORKFLOW when running in GitHub Actions.
    .PARAMETER userName
        The name of the user. Default is $ENV:GITHUB_ACTOR when running in GitHub Actions.
    .PARAMETER branchName
        The name of the branch to use for conditional settings. Default is $ENV:GITHUB_REF_NAME when running in GitHub Actions.
    .PARAMETER orgSettingsVariableValue
        The value of the organization settings variable. Default is $ENV:ALGoOrgSettings.
    .PARAMETER repoSettingsVariableValue
        The value of the repository settings variable. Default is $ENV:ALGoRepoSettings.
    .PARAMETER environmentSettingsVariableValue
        The value of the current GitHub environment settings variable, based on workflow context. Default is $ENV:ALGoEnvSettings.
    .PARAMETER environmentName
        The value of the environment name, based on the workflow context. Default is $ENV:ALGoEnvName.
    .PARAMETER customSettings
        JSON formatted string that will be applied last to override any other settings. These settings have the highest precedence.
#>
function ReadSettings {
    Param(
        [string] $baseFolder = "$ENV:GITHUB_WORKSPACE",
        [string] $repoName = "$ENV:GITHUB_REPOSITORY",
        [string] $project = '.',
        [string] $buildMode = "Default",
        [string] $workflowName = "$ENV:GITHUB_WORKFLOW",
        [string] $userName = "$ENV:GITHUB_ACTOR",
        [string] $branchName = "$ENV:GITHUB_REF_NAME",
        [string] $orgSettingsVariableValue = "$ENV:ALGoOrgSettings",
        [string] $repoSettingsVariableValue = "$ENV:ALGoRepoSettings",
        [string] $environmentSettingsVariableValue = "$ENV:ALGoEnvSettings",
        [string] $environmentName = "$ENV:ALGoEnvName",
        [string] $customSettings = ""
    )

    # If the build is triggered by a pull request the refname will be the merge branch. To apply conditional settings we need to use the base branch
    if (($env:GITHUB_EVENT_NAME -eq "pull_request") -and ($branchName -eq $ENV:GITHUB_REF_NAME)) {
        $branchName = $env:GITHUB_BASE_REF
    }

    function GetSettingsObject {
        Param(
            [string] $path
        )

        if (Test-Path $path) {
            try {
                $settings = Get-Content $path -Encoding UTF8 | ConvertFrom-Json
                if ($settings) {
                    return $settings
                }
            }
            catch {
                throw "Error reading $path. Error was $($_.Exception.Message).`n$($_.ScriptStackTrace)"
            }
        }
        return $null
    }

    $repoName = $repoName.SubString("$repoName".LastIndexOf('/') + 1)
    $githubFolder = Join-Path $baseFolder ".github"
    $workflowName = SanitizeWorkflowName -workflowName $workflowName

    # Start with default settings
    $settings = GetDefaultSettings -repoName $repoName

    # Read settings from files and merge them into the settings object

    $settingsObjects = @()

    # Read settings from organization settings variable (parameter)
    if ($orgSettingsVariableValue) {
        $orgSettingsVariableObject = $orgSettingsVariableValue | ConvertFrom-Json
        $settingsObjects += @{
            "Source" = "ALGoOrgSettings"
            "Type" = "Variable"
            "Settings" = $orgSettingsVariableObject
        }
    }

    # Read settings from the custom template repository settings file
    $customTemplateRepoSettingsObject = GetSettingsObject -Path (Join-Path $baseFolder $CustomTemplateRepoSettingsFile)
    $settingsObjects += @{
        "Source" = "$CustomTemplateRepoSettingsFile"
        "Type" = "File"
        "Settings" = $customTemplateRepoSettingsObject
    }

    # Read settings from repository settings file
    $repoSettingsObject = GetSettingsObject -Path (Join-Path $baseFolder $RepoSettingsFile)
    $settingsObjects += @{
        "Source" = "$RepoSettingsFile"
        "Type" = "File"
        "Settings" = $repoSettingsObject
    }

    # Read settings from repository settings variable (parameter)
    if ($repoSettingsVariableValue) {
        $repoSettingsVariableObject = $repoSettingsVariableValue | ConvertFrom-Json
        $settingsObjects += @{
            "Source" = "ALGoRepoSettings"
            "Type" = "Variable"
            "Settings" = $repoSettingsVariableObject
        }
    }

    if ($project) {
        $customTemplateProjectSettingsObject = GetSettingsObject -Path (Join-Path $baseFolder $CustomTemplateProjectSettingsFile)
        $settingsObjects += @{
            "Source" = "$CustomTemplateProjectSettingsFile"
            "Type" = "File"
            "Settings" = $customTemplateProjectSettingsObject
        }

        # Read settings from project settings file
        $projectFolder = Join-Path $baseFolder $project -Resolve
        $projectSettingsObject = GetSettingsObject -Path (Join-Path $projectFolder $ALGoSettingsFile)
        $settingsObjects += @{
            "Source" = "$(Join-Path $project $ALGoSettingsFile)"
            "Type" = "File"
            "Settings" = $projectSettingsObject
        }
    }

    if ($workflowName) {
        # Read settings from workflow settings file
        $workflowSettingsObject = GetSettingsObject -Path (Join-Path $githubFolder "$workflowName.settings.json")
        $settingsObjects += @{
            "Source" = "$(Join-Path ".github" "$workflowName.settings.json")"
            "Type" = "File"
            "Settings" = $workflowSettingsObject
        }

        if ($project) {
            # Read settings from project workflow settings file
            $projectWorkflowSettingsObject = GetSettingsObject -Path (Join-Path $projectFolder "$ALGoFolderName/$workflowName.settings.json")
            $settingsObjects += @{
                "Source" = "$(Join-Path $project "$ALGoFolderName/$workflowName.settings.json")"
                "Type" = "File"
                "Settings" = $projectWorkflowSettingsObject
            }

            # Read settings from user settings file
           $userSettingsObject = GetSettingsObject -Path (Join-Path $projectFolder "$ALGoFolderName/$userName.settings.json")
            $settingsObjects += @{
                "Source" = "$(Join-Path $project "$ALGoFolderName/$userName.settings.json")"
                "Type" = "File"
                "Settings" = $userSettingsObject
            }
        }
    }

    if ($environmentSettingsVariableValue) {
        # Read settings from environment variable (parameter)
        $environmentVariableObject = $environmentSettingsVariableValue | ConvertFrom-Json

        # Warn user that 'DeployTo' setting needs to include environment name
        if ($environmentVariableObject.PSObject.Properties.Name -contains "DeployTo") {
            OutputWarning "The environment settings variable contains the property 'DeployTo'. Did you intend to use 'DeployTo$environmentName' instead? The 'DeployTo' property without a specific environment name is not supported."
        }
        # Warn user if 'runs-on', 'shell' or 'ContinuousDeployment' is defined in the environment settings variable, as these are not supported when defined there.
        if ($environmentVariableObject.PSObject.Properties.Name -contains "DeployTo$environmentName") {
            @('runs-on', 'shell', 'ContinuousDeployment') | ForEach-Object {
                if ($environmentVariableObject."DeployTo$environmentName".PSObject.Properties.Name -contains $_) {
                    OutputWarning "The property $_ in the DeployTo setting is not supported when defined within a GitHub deployment environment variable. Please define this property elsewhere."
                }
            }
        }
        $settingsObjects += @{
            "Source" = "ALGoEnvSettings for $environmentName"
            "Type" = "Variable"
            "Settings" = $environmentVariableObject
        }
    }

    # Read custom settings (parameter)
    if ($customSettings) {
        try {
            $customSettingsObject = $customSettings | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse customSettings JSON: $($_.Exception.Message)"
        }
        $settingsObjects += @{
            "Source" = "CustomSettings"
            "Type" = "Parameter"
            "Settings" = $customSettingsObject
        }
    }

    foreach($settingsObject in $settingsObjects) {
        $settingsJson = $settingsObject.Settings
        if ($settingsJson) {
            OutputDebug "Applying settings from $($settingsObject.Source) ($($settingsObject.Type))"
            MergeCustomObjectIntoOrderedDictionary -dst $settings -src $settingsJson
            if ($settingsJson.PSObject.Properties.Name -eq "ConditionalSettings") {
                foreach($conditionalSetting in $settingsJson.ConditionalSettings) {
                    if ("$conditionalSetting" -ne "") {
                        $conditionMet = $true
                        $conditions = @()
                        @{"buildModes" = $buildMode; "branches" = $branchName; "repositories" = $repoName; "projects" = $project; "workflows" = $workflowName; "users" = $userName}.GetEnumerator() | ForEach-Object {
                            $propName = $_.Key
                            $propValue = $_.Value
                            if ($conditionMet -and $conditionalSetting.PSObject.Properties.Name -eq $propName) {

                                # If the property name is workflows then we should sanitize the workflow name in the same way we sanitize the $workflowName variable
                                if($propName -eq "workflows") {
                                    $conditionalSetting."$propName" = $conditionalSetting."$propName" | ForEach-Object { SanitizeWorkflowName -workflowName $_ }
                                }

                                $conditionMet = $propValue -and $conditionMet -and ($conditionalSetting."$propName" | Where-Object { $propValue -like $_ })
                                $conditions += @("$($propName): $propValue")
                            }
                        }
                        if ($conditionMet) {
                            OutputDebug "Applying conditional settings for $($conditions -join ", ")"
                            MergeCustomObjectIntoOrderedDictionary -dst $settings -src $conditionalSetting.settings
                        }
                    }
                }
            }
        }
        else {
            OutputDebug "No settings found in $($settingsObject.Source) ($($settingsObject.Type))"
        }
    }

    # runs-on is used for all jobs except for the build job (basically all jobs which doesn't need a container)
    # gitHubRunner is used for the build job (or basically all jobs that needs a container)
    #
    # shell defaults to "powershell" unless runs-on is Ubuntu (Linux), then it defaults to pwsh
    #
    # gitHubRunner defaults to "runs-on", unless runs-on is Ubuntu (Linux) as this won't work.
    # gitHubRunnerShell defaults to "shell"
    #
    # The exception for keeping gitHubRunner to Windows-Latest (when set to Ubuntu-*) will be removed when all jobs supports Ubuntu (Linux)
    # At some point in the future (likely version 3.0), we will switch to Ubuntu (Linux) as default for "runs-on"
    #
    if ($settings.shell -eq "") {
        if ($settings."runs-on" -like "*ubuntu-*") {
            OutputDebug "Setting shell to pwsh for ubuntu"
            $settings.shell = "pwsh"
        }
        else {
            OutputDebug "Setting shell to powershell for non-ubuntu"
            $settings.shell = "powershell"
        }
    }
    if ($settings.githubRunner -eq "") {
        if ($settings."runs-on" -like "*ubuntu-*") {
            OutputDebug "Setting gitHubRunner to windows-latest for ubuntu"
            $settings.githubRunner = "windows-latest"
        }
        else {
            OutputDebug "Setting gitHubRunner to runs-on value: $($settings."runs-on")"
            $settings.githubRunner = $settings."runs-on"
        }
    }
    if ($settings.githubRunnerShell -eq "") {
        OutputDebug "Setting gitHubRunnerShell to shell value: $($settings.shell)"
        $settings.githubRunnerShell = $settings.shell
    }

    # Check that gitHubRunnerShell and Shell is valid
    if ($settings.githubRunnerShell -ne "powershell" -and $settings.githubRunnerShell -ne "pwsh") {
        throw "Invalid value for setting: gitHubRunnerShell: $($settings.githubRunnerShell)"
    }
    if ($settings.shell -ne "powershell" -and $settings.shell -ne "pwsh") {
        throw "Invalid value for setting: shell: $($settings.githubRunnerShell)"
    }

    if (($settings.githubRunner -like "*ubuntu-*") -and ($settings.githubRunnerShell -eq "powershell")) {
        OutputDebug "Switching shell to pwsh for ubuntu"
        $settings.githubRunnerShell = "pwsh"
    }

    if($settings.projectName -eq '') {
        OutputDebug "Setting projectName to default value: $project"
        $settings.projectName = $project # Default to project path as project name
    }

    $settings | ValidateSettings

    $settings
}

<#
    .SYNOPSIS
        Validate the settings against the settings schema file.
    .PARAMETER settings
        The settings to validate.
#>
function ValidateSettings {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $settings
    )
    Process {
        $settingsJson = ConvertTo-Json -InputObject $settings -Depth 99 -Compress
        $settingsSchemaFile = Join-Path $PSScriptRoot "settings.schema.json" -Resolve

        $result = ""
        try{
            $command  = [scriptblock] {
                $result = ''
                Test-Json -Json $args[0] -SchemaFile $args[1] -ErrorVariable result -ErrorAction SilentlyContinue | Out-Null
                return $result
            }

            if($PSVersionTable.PSVersion.Major -lt 6) { # Test-Json is not available in PS5.1
                $result = pwsh -noprofile -Command $command -args $settingsJson, $settingsSchemaFile
            }
            else {
                $result = Invoke-Command -ScriptBlock $command -ArgumentList $settingsJson, $settingsSchemaFile
            }
        }
        catch {
            OutputWarning "Error validating settings. Error: $($_.Exception.Message)"
        }
        if ($result) {
            OutputWarning "Settings are not valid. Error: $result"
        }
    }
}

<#
    .SYNOPSIS
        Sanitize a workflow name by removing invalid file name characters.
    .PARAMETER workflowName
        The workflow name to sanitize.
    .OUTPUTS
        The sanitized workflow name.
#>
function SanitizeWorkflowName {
    Param(
        [string] $workflowName
    )
    return $workflowName.Trim().Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
}

Export-ModuleMember -Function ReadSettings
Export-ModuleMember -Variable ALGoFolderName, ALGoSettingsFile, RepoSettingsFile, CustomTemplateRepoSettingsFile, CustomTemplateProjectSettingsFile, RepoSettingsFileName, ALGoSettingsFileName, CustomTemplateRepoSettingsFileName, CustomTemplateProjectSettingsFileName
