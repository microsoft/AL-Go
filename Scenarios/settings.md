# Settings
The behavior of AL-Go for GitHub is very much controlled by settings.

## Where are the settings located

Settings can be defined in GitHub variables or in various settings file. An AL-Go repository can consist of a single project (with multiple apps) or multiple projects (each with multiple apps). Settings can be applied on the project level or on the repository level. Multiple projects in a single repository are comparable to multiple repositories; they are built, deployed, and tested separately. All apps in each project (single or multiple) are built together in the same pipeline, published and tested together. If a repository is multiple projects, each project is stored in a separate folder in the root of the repository.

When running a workflow or a local script, the settings are applied by reading settings from GitHub variables and one or more settings files. Last applied settings file wins. The following lists the order of locations to search for settings:

1.  `ALGoOrgSettings` is a **GitHub variable**, which can be defined on an **organizational level** and will apply to **all AL-Go repositories** in this organization.

1.  `.github/AL-Go-settings.json` is the **repository settings file**. This settings file contains settings that are relevant for all projects in the repository. **Special note:** The repository settings file can also contains `BcContainerHelper` settings, which will be applied when loading `BcContainerHelper` in a workflow - the GitHub variables are not considered for BcContainerHelper settings. (see expert section).

1.  `ALGoRepoSettings` is a **GitHub variable**, which can be defined on an **repository level** and can contain settings that are relevant for **all projects** in the repository.

1.  `.AL-Go/settings.json` is the **project settings file**. If the repository is a single project, the .AL-Go folder is in the root folder of the repository. If the repository contains multiple projects, there will be a .AL-Go folder in each project folder (like `project/.AL-Go/settings.json`)

1.  `.github/<workflow>.settings.json` is the **workflow-specific settings file** for **all projects**. This option is used for the Current, NextMinor and NextMajor workflows to determine artifacts and build numbers when running these workflows.

1.  `.AL-Go/<workflow>.settings.json` is the **workflow-specific settings file** for a **specific project**.

1.  `.AL-Go/<username>.settings.json` is the **user-specific settings file**. This option is rarely used, but if you have special settings, which should only be used for one specific user (potentially in the local scripts), these settings can be added to a settings file with the name of the user followed by `.settings.json`.

## Basic settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="country"></a>country | Specifies which country this app is built against. | us |
| <a id="repoVersion"></a>repoVersion | RepoVersion is the repository version number. The Repo Version number consists of \<major\>.\<minor\> only and is used for naming build artifacts in the CI/CD workflow. Build artifacts are named **\<project\>-Apps-\<repoVersion\>.\<build\>.\<revision\>** and can contain multiple apps. The Repo Version number is used as major.minor for individual apps if versioningStrategy is +16. | 1.0 |
| <a id="projectName"></a>projectName | Friendly name for an AL-Go project to be used in the UI for various workflows (CICD, Pull Request Build, etc.). If not set, the name for the project will be the relative path from the root of the repository. | '' |
| <a id="appFolders"></a>appFolders | appFolders should be an array of folders (relative to project root), which contains apps for this project. Apps in these folders are sorted based on dependencies and built and published in that order.<br />If appFolders are not specified, AL-Go for GitHub will try to locate appFolders in the root of the project. | [ ] |
| <a id="testFolders"></a>testFolders | testFolders should be an array of folders (relative to project root), which contains test apps for this project. Apps in these folders are sorted based on dependencies and built, published and tests are run in that order.<br />If testFolders are not specified, AL-Go for GitHub will try to locate testFolders in the root of the project. | [ ] |
| <a id="bcptTestFolders"></a>bcptTestFolders | bcptTestFolders should be an array of folders (relative to project root), which contains performance test apps for this project. Apps in these folders are sorted based on dependencies and built, published and bcpt tests are run in that order.<br />If bcptTestFolders are not specified, AL-Go for GitHub will try to locate bcptTestFolders in the root of the project. | [ ] |
| <a id="appDependencyProbingPaths"></a>appDependencyProbingPaths | Array of dependency specifications, from which apps will be downloaded when the CI/CD workflow is starting. Every dependency specification consists of the following properties:<br />**repo** = repository<br />**version** = version (default latest)<br />**release_status** = latestBuild/release/prerelease/draft (default release)<br />**projects** = projects (default * = all)<br />**AuthTokenSecret** = Name of secret containing auth token (default none)<br /> | [ ] |
| <a id="cleanModePreprocessorSymbols"></a>cleanModePreprocessorSymbols | List of clean tags to be used in _Clean_ build mode | [ ] |

## AppSource specific basic settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="appSourceCopMandatoryAffixes"></a>appSourceCopMandatoryAffixes | This setting is only used if the type is AppSource App. The value is an array of affixes, which is used for running AppSource Cop. | [ ] |
| <a id="appSourceProductId"></a>appSourceProductId<br /><a id="appSourceMainAppFolder"></a>appSourceMainAppFolder<br /><a id="appSourceContinuousDelivery"></a>appSourceContinuousDelivery | Use these settings to enable publishing of apps to AppSource directly from AL-Go for GitHub.<br />**appSourceProductId** must be the product Id from partner Center.<br />**appSourceMainAppFolder** specifies the appFolder of the main app if you have multiple apps in the same project.<br />**appSourceContinuousDelivery** can be set to true to enable continuous delivery of every successful build to AppSource Validation. Note that the app will only be in preview in AppSource and you will need to manually press GO LIVE in order for the app to be promoted to production.<br />**Note:** You will need to define an AppSourceContext secret in order to publish to AppSource. | |
| <a id="obsoleteTagMinAllowedMajorMinor"></a>obsoleteTagMinAllowedMajorMinor | This setting will enable AppSource cop rule AS0105, which causes objects that are pending obsoletion with an obsolete tag version lower than the minimum set in this property are not allowed. | |

## Basic Repository settings
The repository settings are only read from the repository settings file (.github\AL-Go-Settings.json)

| Name | Description |
| :-- | :-- |
| <a id="type"></a>type | Specifies the type of project. Allowed values are **PTE** or **AppSource App**. This value comes with the default repository. Default value is PTE. |
| <a id="templateUrl"></a>templateUrl | Defines the URL of the template repository used to create this project and is used for checking and downloading updates to AL-Go System files. |
| <a id="nextMajorSchedule"></a>nextMajorSchedule | CRON schedule for when NextMajor workflow should run. Default is no scheduled run, only manual trigger. Build your CRON string here: [https://crontab.guru](https://crontab.guru) |
| <a id="nextMinorSchedule"></a>nextMinorSchedule | CRON schedule for when NextMinor workflow should run. Default is no scheduled run, only manual trigger. Build your CRON string here: [https://crontab.guru](https://crontab.guru) |
| <a id="currentSchedule"></a>currentSchedule | CRON schedule for when Current workflow should run. Default is no scheduled run, only manual trigger. Build your CRON string here: [https://crontab.guru](https://crontab.guru) |
| <a id="runs-on"></a>runs-on | Specifies which github runner will be used for all jobs in all workflows (except the Update AL-Go System Files workflow). The default is to use the GitHub hosted runner _windows-latest_. You can specify a special GitHub Runner for the build job using the GitHubRunner setting. Read [this](SelfHostedGitHubRunner.md) for more information.<br />Setting runs-on to _ubuntu-latest_ will run all non-build jobs on Linux, build jobs will still run _windows-latest_ (or whatever you have set in **githubRunner**) |
| <a id="shell"></a>shell | Specifies which shell will be used as the default in all jobs. **powershell** is the default, which results in using _PowerShell 5.1_ (unless you selected _ubuntu-latest_, then **pwsh** is used, which results in using _PowerShell 7_) |
| <a id="githubRunner"></a>githubRunner | Specifies which github runner will be used for the build jobs in workflows including a build job. This is the most time consuming task. By default this job uses the _Windows-latest_ github runner (unless overridden by the runs-on setting). This settings takes precedence over runs-on so that you can use different runners for the build job and the housekeeping jobs. See **runs-on** setting. |
| <a id="githubRunnerShell"></a>githubRunnerShell | Specifies which shell is used for build jobs in workflows including a build job. The default is to use the same as defined in **shell**. If the shell setting isn't defined, **powershell** is the default, which results in using _PowerShell 5.1_. Use **pwsh** for _PowerShell 7_. |
| <a id="environments"></a>environments | Array of logical environment names. You can specify environments in GitHub environments or in the repo settings file. If you specify environments in the settings file, you can create your AUTHCONTEXT secret using **&lt;environmentname&gt;_AUTHCONTEXT**. You can specify additional information about environments in a setting called **DeployTo&lt;environmentname&gt;** | [ ] |
| <a id="deployto"></a>DeployTo&lt;environmentname&gt; | Structure with additional properties for the environment specified. The structure can contain the following properties:<br />**EnvironmentType** = specifies the type of environment. The environment type can be used to invoke a custom deployment. (Default SaaS)<br />**EnvironmentName** = specifies the "real" name of the environment if it differs from the GitHub environment.<br />**Branches** = an array of branch patterns, which are allowed to deploy to this environment. (Default main)<br />**Projects** = In multi-project repositories, this property can be a comma separated list of project patterns to deploy to this environment. (Default *)<br />**SyncMode** = ForceSync if deployment to this environment should happen with ForceSync, else Add. If deploying to the development endpoint you can also specify Development or Clean. (Default Add)<br />**ContinuousDeployment** = true if this environment should be used for continuous deployment, else false. (Default: AL-Go will continuously deploy to sandbox environments or environments, which doesn't end in (PROD) or (FAT)<br />**runs-on** = specifies which runner to use when deploying to this environment. (Default is settings.runs-on)<br /> | { } |
| <a id="useProjectDependencies"></a>useProjectDependencies | Determines whether your projects are built using a multi-stage built workflow or single stage. After setting useProjectDependencies to true, you need to run Update AL-Go System Files and your workflows including a build job will change to have multiple build jobs, depending on each other. The number of build jobs will be determined by the dependency depth in your projects.<br />You can change dependencies between your projects, but if the dependency **depth** changes, AL-Go will warn you that updates for your AL-Go System Files are available and you will need to run the workflow. |
| <a id="CICDPushBranches"></a>CICDPushBranches | CICDPushBranches can be specified as an array of branches, which triggers a CI/CD workflow on commit.<br />Default is [ "main", "release/\*", "feature/\*" ] |
| <a id="CICDPullrequestBranches"></a>CICDPullRequestBranches | CICDPullRequestBranches can be specified as an array of branches, which triggers a CI/CD workflow on a PR.<br />Default is [ "main" ] |
| <a id="PullRequestTrigger"></a>PullRequestTrigger | Setting for specifying the trigger AL-Go should use to trigger Pull Request Builds. By default it is set to [pull_request_target](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request_target) |
| <a id="CICDSchedule"></a>CICDSchedule | CRON schedule for when CI/CD workflow should run. Default is no scheduled run, only manually triggered or triggered by Push or Pull Request. Build your CRON string here: [https://crontab.guru](https://crontab.guru) |
| <a id="UpdateGitHubGoSystemFilesSchedule"></a>UpdateGitHubGoSystemFilesSchedule | CRON schedule for when Update AL-Go System Files should run. When Update AL-Go System Files runs on a schedule, it uses direct COMMIT instead of creating a PR. Default is no scheduled run, only manual trigger. Build your CRON string here: [https://crontab.guru](https://crontab.guru) |
| <a id="buildModes"></a>buildModes | A list of build modes to use when building the AL-Go projects. Every AL-Go projects will be built using each built mode. Available build modes are:<br /> **Default**: Apps are compiled as they are in the source code.<br />**Clean**: _PreprocessorSymbols_ are enabled when compiling the apps. The values for the symbols correspond to the `cleanModePreprocessorSymbols` setting of the AL-Go project.<br />**Translated**: `TranslationFile` compiler feature is enabled when compiling the apps. |

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="artifact"></a>artifact | Determines the artifacts used for building and testing the app.<br />This setting can either be an absolute pointer to Business Central artifacts (https://... - rarely used) or it can be a search specification for artifacts (\<storageaccount\>/\<type\>/\<version\>/\<country\>/\<select\>/\<sastoken\>).<br />If not specified, the artifacts used will be the latest sandbox artifacts from the country specified in the country setting. | |
| <a id="updateDependencies"></a>updateDependencies | Setting updateDependencies to true causes AL-Go to build your app against the first compatible Business Central build and set the dependency version numbers in the app.json accordingly during build. All version numbers in the built app will be set to the version number used during compilation. | false |
| <a id="generateDependencyArtifact"></a>generateDependencyArtifact | When this repository setting is true, CI/CD pipeline generates an artifact with the external dependencies used for building the apps in this repo. | false |
| <a id="companyName"></a>companyName | Company name selected in the database, used for running the CI/CD workflow. Default is to use the default company in the selected Business Central localization. | |
| <a id="versioningStrategy"></a>versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 tuples: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app. **Build** and **Revision** are calculated. Currently 3 versioning strategies are supported:<br />**0** = **Build** is the **github [run_number](https://go.microsoft.com/fwlink/?linkid=2217416&clcid=0x409)** for the CI/CD workflow, increased by the **runNumberOffset** setting value (if specified). **Revision** is the **github [run_attempt](https://go.microsoft.com/fwlink/?linkid=2217416&clcid=0x409)** subtracted 1.<br />**2** = **Build** is the current date  as **yyyyMMdd**. **Revision** is the current time as **hhmmss**. Date and time are always **UTC** timezone to avoid problems during daylight savings time change. Note that if two CI/CD workflows are started within the same second, this could yield to identical version numbers from two different runs.<br />**+16** use **repoVersion** setting as **appVersion** (**Major** and **Minor**) for all apps | 0 |
| <a id="additionalCountries"></a>additionalCountries | This property can be set to an additional number of countries to compile, publish and test your app against during workflows. Note that this setting can be different in NextMajor and NextMinor workflows compared to the CI/CD workflow, by specifying a different value in a workflow settings file. | [ ] |
| <a id="keyVaultName"></a>keyVaultName | When using Azure KeyVault for the secrets used in your workflows, the KeyVault name needs to be specified in this setting if it isn't specified in the AZURE_CREDENTIALS secret. Read [this](UseAzureKeyVault.md) for more information. | |
| <a id="licenseFileUrlSecretName"></a>licenseFileUrlSecretName | Specify the name (**NOT the secret**) of the LicenseFileUrl secret. Default is LicenseFileUrl. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as LicenseFileUrl. A LicenseFileUrl is required when building AppSource apps for Business Central prior to version 22. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | LicenseFileUrl |
| <a id="insiderSasTokenSecretName"></a>insiderSasTokenSecretName | Specifies the name (**NOT the secret**) of the InsiderSasToken secret. Default is InsiderSasToken. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as InsiderSasToken for getting access to Next Minor and Next Major builds. | InsiderSasToken |
| <a id="ghTokenWorkflowSecretName"></a>ghTokenWorkflowSecretName | Specifies the name (**NOT the secret**) of the GhTokenWorkflow secret. Default is GhTokenWorkflow. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as Personal Access Token with permission to modify workflows when running the Update AL-Go System Files workflow. Read [this](UpdateAlGoSystemFiles.md) for more information. | GhTokenWorkflow |
| <a id="adminCenterApiCredentialsSecretName"></a>adminCenterApiCredentialsSecretName | Specifies the name (**NOT the secret**) of the adminCenterApiCredentials secret. Default is adminCenterApiCredentials. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use when connecting to the Admin Center API when creating Online Development Environments. Read [this](CreateOnlineDevEnv2.md) for more information. | AdminCenterApiCredentials |
| <a id="installApps"></a>installApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installApps are downloaded and installed before compiling and installing the apps. | [ ] |
| <a id="installTestApps"></a>installTestApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installTestApps are downloaded and installed before compiling and installing the test apps. Adding a parantheses around the setting indicates that the test in this app will NOT be run, only installed. | [ ] |
| <a id="configPackages"></a>configPackages | An array of configuration packages to be applied to the build container before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="configPackages.country"></a>configPackages.country | An array of configuration packages to be applied to the build container for country **country** before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="installOnlyReferencedApps"></a>installOnlyReferencedApps | By default, only the apps referenced in the dependency chain of your apps will be installed when inspecting the settings: InstallApps, InstallTestApps and appDependencyProbingPath. If you change this setting to false, all apps found will be installed. | true |
| <a id="enableCodeCop"></a>enableCodeCop | If enableCodeCop is set to true, the CI/CD workflow will enable the CodeCop analyzer when building. | false |
| <a id="enableUICop"></a>enableUICop | If enableUICop is set to true, the CI/CD workflow will enable the UICop analyzer when building. | false |
| <a id="customCodeCops"></a>customCodeCops | CustomCodeCops is an array of paths or URLs to custom Code Cop DLLs you want to enable when building. | [ ] |
| <a id="failOn"></a>failOn | Specifies what the pipeline will fail on. Allowed values are none, warning and error | error |
| <a id="rulesetFile"></a>rulesetFile | Filename of the custom ruleset file | |
| <a id="vsixFile"></a>vsixFile | A direct download URL, pointing to the AL Language VSIX file to use for building the apps. By default, AL-Go uses the AL Language extension, which is shipped with the artifacts used for the build. | |
| <a id="codeSignCertificateUrlSecretName"></a>codeSignCertificateUrlSecretName<br />codeSignCertificatePasswordSecretName | When developing AppSource Apps, your app needs to be code signed and you need to add secrets to GitHub secrets or Azure KeyVault, specifying the secure URL from which your codesigning certificate pfx file can be downloaded and the password for this certificate. These settings specifies the names (**NOT the secrets**) of the code signing certificate url and password. Default is to look for secrets called CodeSignCertificateUrl and CodeSignCertificatePassword. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | CodeSignCertificateUrl<br />CodeSignCertificatePassword |
| <a id="keyVaultCodesignCertificateName"></a>keyVaultCodesignCertificateName | Name of a certificate stored in your KeyVault that can be used to codesigning. To use this setting you will also need enable Azure KeyVault in your AL-GO project. Read [this](UseAzureKeyVault.md) for more information | |
| <a id="applicationInsightsConnectionStringSecretName"></a>applicationInsightsConnectionStringSecretName | This setting specifies the name (**NOT the secret**) of a secret containing the application insights connection string for the apps. | applicationInsightsConnectionString |
| <a id="storageContextSecretName"></a>storageContextSecretName | This setting specifies the name (**NOT the secret**) of a secret containing a json string with StorageAccountName, ContainerName, BlobName and StorageAccountKey or SAS Token. If this secret exists, AL-Go will upload builds to this storage account for every successful build.<br />The BcContainerHelper function New-ALGoStorageContext can create a .json structure with this content. | StorageContext |
| <a id="alwaysBuildAllProjects"></a>alwaysBuildAllProjects | This setting only makes sense if the repository is setup for multiple projects.<br />Standard behavior of the CI/CD workflow is to only build the projects, in which files have changes when running the workflow due to a push or a pull request | false |
| <a id="fullBuildPatterns"></a>fullBuildPatterns | Use this setting to list important files and folders. Changes to any of these files and folders would trigger a full Pull Request build (all AL-Go projects will be built). <br /> *Examples*:<br /> 1. Specifying `fullBuildPatterns` as `[ "Build/*" ]` means that any changes from a PR to the `Build` folder would trigger a full build. <br /> 2. Specifying `fullBuildPatterns` as `[ "*" ]` means that any changes from a PR would trigger a full build and it is equivalent to setting `alwaysBuildAllProjects` to `true`.  | [ ] |
| <a id="skipUpgrade"></a>skipUpgrade | This setting is used to signal to the pipeline to NOT run upgrade and ignore previous releases of the app. | false |
| <a id="cacheImageName"></a>cacheImageName | When using self-hosted runners, cacheImageName specifies the prefix for the docker image created for increased performance | my |
| <a id="cacheKeepDays"></a>cacheKeepDays | When using self-hosted runners, cacheKeepDays specifies the number of days docker image are cached before cleaned up when running the next pipeline.<br />Note that setting cacheKeepDays to 0 will flush the cache before every build and will cause all other running builds using agents on the same host to fail. | 3 |
| <a id="assignPremiumPlan"></a>assignPremiumPlan | Setting assignPremiumPlan to true in your project setting file, causes the build container to be created with the AssignPremiumPlan set. This causes the auto-created user to have Premium Plan enabled. This setting is needed if your tests require premium plan enabled. | false |
| <a id="enableTaskScheduler"></a>enableTaskScheduler | Setting enableTaskScheduler to true in your project setting file, causes the build container to be created with the Task Scheduler running. | false |
| <a id="useCompilerFolder"></a>useCompilerFolder | Setting useCompilerFolder to true causes your pipelines to use containerless compiling. Unless you also set **doNotPublishApps** to true, setting useCompilerFolder to true won't give you any performance advantage, since AL-Go for GitHub will still need to create a container in order to publish and test the apps. In the future, publishing and testing will be split from building and there will be other options for getting an instance of Business Central for publishing and testing. | false |
| <a id="excludeEnvironments"></a>excludeEnvironments | excludeEnvironments can be an array of GitHub Environments, which should be excluded from the list of environments considered for deployment. github_pages is automatically added to this array and cannot be used as environment for deployment of AL-Go for GitHub projects. | [ ] |

## AppSource specific advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id=""></a>appSourceContextSecretName | This setting specifies the name (**NOT the secret**) of a secret containing a json string with ClientID, TenantID and ClientSecret or RefreshToken. If this secret exists, AL-Go will can upload builds to AppSource validation. | AppSourceContext |
| <a id=""></a>keyVaultCertificateUrlSecretName<br />keyVaultCertificatePasswordSecretName<br />keyVaultClientIdSecretName | If you want to enable KeyVault access for your AppSource App, you need to provide 3 secrets as GitHub Secrets or in the Azure KeyVault. The names of those secrets (**NOT the secrets**) should be specified in the settings file with these 3 settings. Default is to not have KeyVault access from your AppSource App. Read [this](EnableKeyVaultForAppSourceApp.md) for more information. | |

## Conditional Settings
In any of the settings files, you can add conditional settings by using the ConditionalSettings setting.

Example, adding this:
```json
    "ConditionalSettings": [
        {
            "branches": [
                "feature/*"
            ],
            "settings": {
                "doNotPublishApps": true,
                "doNotSignApps": true
            }
        }
    ]
```
to your project settings file (.AL-Go/settings.json) will ensure that all branches matching the patterns in branches will use doNotPublishApps=true and doNotSignApps=true during CI/CD. Conditions can be:
- **repositories** settings will be applied to repositories matching the patterns
- **projects** settings will be applied to projects matching the patterns
- **branches** settings will be applied to branches matching the patterns
- **workflows** settings will be applied to workflows matching the patterns
- **users** settings will be applied for users matching the patterns

You could imagine that you could have and organizational settings variable containing:

```json
    "ConditionalSettings": [
        {
            "repositories": [
                "bcsamples-*"
            ],
            "branches": [
                "features/*"
            ],
            "settings": {
                "doNotSignApps": true
            }
        }
    ]
```

Which will ensure that for all repositories named `bcsamples-*` in this organization, the branches matching `features/*` will not sign apps.

**Note:** that you can have conditional settings on any level and all conditional settings which has all conditions met will be applied in the order of settings file + appearance.

## Expert settings (rarely used)

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="repoName"></a>repoName | the name of the repository | name of GitHub repository |
| <a id="runNumberOffset"></a>runNumberOffset | when using **VersioningStrategy** 0, the CI/CD workflow uses the GITHUB RUN_NUMBER as the build part of the version number as described under VersioningStrategy. The RUN_NUMBER is ever increasing and if you want to reset it, when increasing the Major or Minor parts of the version number, you can specify a negative number as runNumberOffset. You can also provide a positive number to get a starting offset. Read about RUN_NUMBER [here](https://go.microsoft.com/fwlink/?linkid=2217059&clcid=0x409) | 0 |
| <a id="applicationDependency"></a>applicationDependency | Application dependency defines the lowest Business Central version supported by your app (Build will fail early if artifacts used are lower than this). The value is calculated by reading app.json for all apps, but cannot be lower than the applicationDependency setting which has a default value of 18.0.0.0 | 18.0.0.0 |
| <a id="installTestRunner"></a>installTestRunner | Determines whether the test runner will be installed in the pipeline. If there are testFolders in the project, this setting will be true. | calculated |
| <a id="installTestFramework"></a>installTestFramework | Determines whether the test framework apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test framework apps, this setting will be true | calculated |
| <a id="installTestLibraries"></a>installTestLibraries | Determines whether the test libraries apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test library apps, this setting will be true | calculated |
| <a id="installPerformanceToolkit"></a>installPerformanceToolkit | Determines whether the performance test toolkit apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the performance test toolkit apps, this setting will be true | calculated |
| <a id="enableAppSourceCop"></a>enableAppSourceCop | Determines whether the AppSourceCop will be enabled in the pipeline. If the project type is AppSource App, then the AppSourceCop will be enabled by default. You can set this value to false to force the AppSourceCop to be disabled | calculated |
| <a id="enablePerTenantExtensionCop"></a>enablePerTenantExtensionCop | Determines whether the PerTenantExtensionCop will be enabled in the pipeline. If the project type is PTE, then the PerTenantExtensionCop will be enabled by default. You can set this value to false to force the PerTenantExtensionCop to be disabled | calculated |
| <a id="doNotBuildTests"></a>doNotBuildTests | This setting forces the pipeline to NOT build and run the tests and performance tests in testFolders and bcptTestFolders | false |
| <a id="doNotRunTests"></a>doNotRunTests | This setting forces the pipeline to NOT run the tests in testFolders. Tests are still being built and published. Note this setting can be set in a workflow specific settings file to only apply to that workflow | false |
| <a id="doNotRunBcptTests"></a>doNotRunBcptTests | This setting forces the pipeline to NOT run the performance tests in testFolders. Performance tests are still being built and published. Note this setting can be set in a workflow specific settings file to only apply to that workflow | false |
| <a id="memoryLimit"></a>memoryLimit | Specifies the memory limit for the build container. By default, this is left to BcContainerHelper to handle and will currently be set to 8G | 8G |
| <a id="BcContainerHelperVersion"></a>BcContainerHelperVersion | This setting can be set to a specific version (ex. 3.0.8) of BcContainerHelper to force AL-Go to use this version. **latest** means that AL-Go will use the latest released version. **preview** means that AL-Go will use the latest preview version. **dev** means that AL-Go will use the dev branch of containerhelper. | latest (or preview for AL-Go preview) |
| <a id="unusedALGoSystemFiles"></a>unusedALGoSystemFiles | An array of AL-Go System Files, which won't be updated during Update AL-Go System Files. They will instead be removed.<br />Use this setting with care, as this can break the AL-Go for GitHub functionality and potentially leave your repo no longer functional. | [ ] |

# Expert level

## Custom Delivery

You can override existing AL-Go Delivery functionality or you can define your own custom delivery mechanism for AL-Go for GitHub, by specifying a PowerShell script named DeliverTo*.ps1 in the .github folder. The following example will spin up a delivery job to SharePoint on CI/CD and Release.

DeliverToSharePoint.ps1
```
Param(
    [Hashtable]$parameters
)

Write-Host "Current project path: $($parameters.project)"
Write-Host "Current project name: $($parameters.projectName)"
Write-Host "Delivery Type (CD or Release): $($parameters.type)"
Write-Host "Folder containing apps: $($parameters.appsFolder)"
Write-Host "Folder containing test apps: $($parameters.testAppsFolder)"
Write-Host "Folder containing dependencies (requires generateDependencyArtifact set to true): $($parameters.dependenciesFolder)"

Write-Host "Repository settings:"
$parameters.RepoSettings | Out-Host
Write-Host "Project settings:"
$parameters.ProjectSettings | Out-Host
```

**Note:** You can also override existing AL-Go for GitHub delivery functionality by creating a script called f.ex. DeliverToStorage.ps1 in the .github folder.

Here are the parameters to use in your custom script:

| Parameter | Description | Example |
| --------- | :--- | :--- |
| `$parametes.project` | The current AL-Go project | Root/AllProjects/MyProject |
| `$parameters.projectsName` | The name of the current AL-Go project | Root_AllProjects_MyProject |
| `$parameters.type` | Type of delivery (CD or Release) | CD |
| `$parameters.appsFolder` | The folder that contains the build artifacts from the default build of the non-test apps in the AL-Go project | AllProjects_MyProject-main-Apps-1.0.0.0 |
| `$parameters.testAppsFolder` | The folder that contains the build artifacts from the default build of the test apps in the AL-Go project | AllProjects_MyProject-main-TestApps-1.0.0.0 |
| `$parameters.dependenciesFolder` | The folder that contains the dependencies of the the AL-Go project for the default build | AllProjects_MyProject-main-Dependencies-1.0.0.0 |
| `$parameters.appsFolders` | The folders that contain the build artifacts from all builds (from different build modes) of the non-test apps in the AL-Go project | AllProjects_MyProject-main-Apps-1.0.0.0, AllProjects_MyProject-main-CleanApps-1.0.0.0 |
| `$parameters.testAppsFolders` | The folders that contain the build artifacts from all builds (from different build modes) of the test apps in the AL-Go project | AllProjects_MyProject-main-TestApps-1.0.0.0, AllProjects_MyProject-main-CleanTestApps-1.0.0.0 |
| `$parameters.dependenciesFolders` | The folders that contain the dependencies of the AL-Go project for all builds (from different build modes) | AllProjects_MyProject-main-Dependencies-1.0.0.0, AllProjects_MyProject-main-CleanDependencies-1.0.0.0 |

## Custom Deployment

You can override existing AL-Go Deployment functionality or you can define your own custom deployment mechanism for AL-Go for GitHub. By specifying a PowerShell script named `DeployTo<EnvironmentType>.ps1` in the .github folder. Default Environment Type is SaaS, but you can define your own type by specifying EnvironmentType in the `DeployTo<EnvironmentName>` setting. The following example will spin up a deployment job to SharePoint on CI/CD and Publish To Environment.

DeployToMyEnvironment.ps1
```
Param(
    [Hashtable]$parameters
)

Write-Host "Deployment Type (CD or Release): $($parameters.type)"
Write-Host "Apps to deploy: $($parameters.apps)"
Write-Host "Environment Type: $($parameters.EnvironmentType)"
Write-Host "Environment Name: $($parameters.EnvironmentName)"
```

**Note:** You can also create one script to override all deployment functionality, by creating a script called Deploy.ps1 in the .github folder.

Here are the parameters to use in your custom script:

| Parameter | Description | Example |
| --------- | :--- | :--- |
| `$parameters.type` | Type of delivery (CD or Release) | CD |
| `$parameters.apps` | Apps to deploy | /home/runner/.../GHP-Common-main-Apps-2.0.33.0.zip |
| `$parameters.EnvironmentType` | Environment type | SaaS |
| `$parameters.EnvironmentName` | Environment name | Production |
| `$parameters.Branches` | Branches which should deploy to this environment (from settings) | main,dev |
| `$parameters.AuthContext` | AuthContext in a compressed Json structure | {"refreshToken":"mytoken"} |
| `$parameters.BranchesFromPolicy` | Branches which should deploy to this environment (from GitHub environments) | main |
| `$parameters.Projects` | Projects to deploy to this environment | |
| `$parameters.ContinuousDeployment` | Is this environment setup for continuous deployment | false |
| `$parameters."runs-on"` | GitHub runner to be used to run the deployment script | windows-latest |

## Run-AlPipeline script override

AL-Go for GitHub utilizes the Run-AlPipeline function from BcContainerHelper to perform the actual build (compile, publish, test etc). The Run-AlPipeline function supports overriding functions for creating containers, compiling apps and a lot of other things.

This functionality is also available in AL-Go for GitHub, by adding a file to the .AL-Go folder, you automatically override the function.

| Override | Description |
| :-- | :-- |
| DockerPull.ps1 | Pull the image specified by the parameter $imageName |
| NewBcContainer.ps1 | Create the container using the parameters transferred in the $parameters hashtable |
| ImportTestToolkitToBcContainer.ps1 | Import the test toolkit apps specified by the $parameters hashtable |
| CompileAppInBcContainer.ps1 | Compile the apps specified by the $parameters hashtable |
| GetBcContainerAppInfo.ps1 | Get App Info for the apps specified by the $parameters hashtable |
| PublishBcContainerApp.ps1 | Publish apps specified by the $parameters hashtable |
| UnPublishBcContainerApp.ps1 | UnPublish apps specified by the $parameters hashtable |
| InstallBcAppFromAppSource.ps1 | Install apps from AppSource specified by the $parameters hashtable |
| SignBcContainerApp.ps1 | Sign apps specified by the $parameters hashtable|
| ImportTestDataInBcContainer.ps1 | If this function is provided, it is expected to insert the test data needed for running tests |
| RunTestsInBcContainer.ps1 | Run the tests specified by the $parameters hashtable |
| GetBcContainerAppRuntimePackage.ps1 | Get the runtime package specified by the $parameters hashtable |
| RemoveBcContainer.ps1 | Cleanup based on the $parameters hashtable |
| InstallMissingDependencies | Install missing dependencies |

## BcContainerHelper settings

The repo settings file (.github\\AL-Go-Settings.json) can contain BcContainerHelper settings. Some BcContainerHelper settings are machine specific (folders and like), and should not be set in the repo settings file.

Settings, which might be relevant to set in the settings file includes

| Setting | Description | Default |
| :-- | :-- | :-- |
| baseUrl | The Base Url for the online Business Central Web Client. This should be changed when targetting embed apps. | [https://businesscentral.dynamics.com](https://businesscentral.dynamics.com) |
| apiBaseUrl | The Base Url for the online Business Central API endpoint. This should be changed when targetting embed apps. | [https://api.businesscentral.dynamics.com](https://api.businesscentral.dynamics.com) |
| PartnerTelemetryConnectionString | The Telemetry Connection String for partner telemetry for DevOps telemetry. | |
| SendExtendedTelemetryToMicrosoft | Set this value to true if you agree to emit extended DevOps telemetry to Microsoft. | false |
| ObjectIdForInternalUse | BcContainerHelper will use this Object ID for internal purposes. Change if the default Object ID is in use. | 88123 |
| TreatWarningsAsErrors | A list of AL warning codes, which should be treated as errors | [ ] |
| DefaultNewContainerParameters | A list of parameters to be added to all container creations in this repo | { } |

## Your own version of AL-Go for GitHub

For experts only, following the description [here](Contribute.md) you can setup a local fork of **AL-Go for GitHub** and use that as your templates. You can fetch upstream changes from Microsoft regularly to incorporate these changes into your version and this way have your modified version of AL-Go for GitHub.

**Note:** Our goal is to never break repositories, which are using AL-Go for GitHub as their template. We almost certainly will break you if you create local modifications to scripts and pipelines.

---
[back](../README.md)
