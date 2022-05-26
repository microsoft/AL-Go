# Settings
The behavior of AL-Go for GitHub is very much controlled by the settings in the settings file.

## Where is the settings file located
An AL-Go repository can consist of a single project (with multiple apps) or multiple projects (each with multiple apps). Multiple projects in a single repository are comparable to multiple repositories; they are built, deployed, and tested separately. All apps in each project (single or multiple) are built together in the same pipeline, published and tested together. If a repository is multiple projects, each project is stored in a separate folder in the root of the repository.

When running a workflow or a local script, the settings are applied by reading one or more settings files. Last applied settings file wins. The following lists the settings files and their location:

**.github\\AL-Go-settings.json** is the repository settings file. This settings file contains settings that are relevant for all projects in the repository. If a settings in the repository settings file is found in a subsequent settings file, it will be overridden by the new value.

**Special note:** The repository settings file can also contains `BcContainerHelper` settings, which will be applied when loading `BcContainerHelper` in a workflow (see expert section).

**.AL-Go\\settings.json** is the project settings file. If the repository is a single project, the .AL-Go folder is in the root folder of the repository. If the repository contains multiple projects, there will be a .AL-Go folder in each project folder.

**.AL-Go\\\<workflow\>.settings.json** is the workflow-specific settings file. This option is used for the Current, NextMinor and NextMajor workflows to determine artifacts and build numbers when running these workflows.

**.AL-Go\\\<username\>.settings.json** is the user-specific settings file. This option is rarely used, but if you have special settings, which should only be used for one specific user (potentially in the local scripts), these settings can be added to a settings file with the name of the user followed by `.settings.json`.

## Basic settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| type | Specifies the type of project. Allowed values are **PTE** or **AppSource App**. This value comes with the default repository. | PTE |
| country | Specifies which country this app is built against. | us |
| repoVersion | RepoVersion is the repository version number. The repository version number is used for naming build artifacts in the CI/CD workflow. Build artifacts are named **\<project\>-Apps-\<repoVersion\>.\<build\>.\<revision\>** and can contain multiple apps. Individual apps are versioned independent of this setting. | 1.0 |
| appFolders | appFolders should be an array of folders (relative to project root), which contains apps for this project. Apps in these folders are sorted based on dependencies and built and published in that order. | [ ] |
| testFolders | testFolders should be an array of folders (relative to project root), which contains test apps for this project. Apps in these folders are sorted based on dependencies and built, published and tests are run in that order. | [ ] |
| appSourceCopMandatoryAffixes | This setting is only used if the type is AppSource App. The value is an array of affixes, which is used for running AppSource Cop. | [ ] |
| appDependencyProbingPaths | Array of dependency specifications, from which apps will be downloaded when the CI/CD workflow is starting. Every dependency specification consists of the following properties:<br />**repo** = repository<br />**version** = version (default latest)<br />**release_status** = latestBuild/release/prerelease/draft (default latestBuild)<br />**projects** = projects (default * = all)<br />**AuthTokenSecret** = Name of secret containing auth token (default none)<br /> | [ ] |
| environments | Array of logical environment names. You can specify environments in GitHub environments or in the repo settings file. If you specify environments in the settings file, you can create your AUTHCONTEXT secret using **&lt;environmentname&gt;_AUTHCONTEXT**. If the actual environment name is different from the logical environmentname, then you can create a secret with the actual name called **&lt;environmentname&gt;_ENVIRONMENTNAME** | [ ] |

## Basic Repository settings
The repository settings are only read from the repository settings file (.github\AL-Go-Settings.json)

| Name | Description |
| :-- | :-- |
| templateUrl | Defines the URL of the template repository used to create this project and is used for checking and downloading updates to AL-Go System files. |
| nextMajorSchedule | CRON schedule for when NextMajor workflow should run. Default is no scheduled run, only manual trigger. Build your CRON string here: https://crontab.guru |
| nextMinorSchedule | CRON schedule for when NextMinor workflow should run. Default is no scheduled run, only manual trigger. Build your CRON string here: https://crontab.guru |
| currentSchedule | CRON schedule for when Current workflow should run. Default is no scheduled run, only manual trigger. Build your CRON string here: https://crontab.guru |
| githubRunner | Specifies which github runner will be used for the pipeline, which is the most time consuming task. Currently, you cannot change which runner is used for all the house-keeping tasks. These will always be run on the default github hosted runner: windows-latest. Read [this](SelfHostedGitHubRunner.md) for more information.

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| artifact | Determines the artifacts used for building and testing the app.<br />This setting can either be an absolute pointer to Business Central artifacts (https://... - rarely used) or it can be a search specification for artifacts (\<storageaccount\>/\<type\>/\<version\>/\<country\>/\<select\>/\<sastoken\>).<br />If not specified, the artifacts used will be the latest sandbox artifacts from the country specified in the country setting. | |
| updateDependencies | Setting updateDependencies to true causes AL-Go to build your app against the first compatible Business Central build and set the dependency version numbers in the app.json accordingly during build. All version numbers in the built app will be set to the version number used during compilation. | false |
| companyName | Company name selected in the database, used for running the CI/CD workflow. Default is to use the default company in the selected Business Central localization. | |
| versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 tuples: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app. **Build** and **Revision** are calculated. Currently 3 versioning strategies are supported:<br />**0** = **Build** is the **github [run_number](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the CI/CD workflow, increased by the **runNumberOffset** setting value (if specified). **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**1** = **Build** is the **github [run_id](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the repository. **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**2** = **Build** is the current date  as **yyyyMMdd**. **Revision** is the current time as **hhmmss**. Date and time are always **UTC** timezone to avoid problems during daylight savings time change. Note that if two CI/CD workflows are started within the same second, this could yield to identical version numbers from two different runs.<br />**+16** use **repoVersion** setting as **appVersion** (**Major** and **Minor**) for all apps | 0 |
| additionalCountries | This property can be set to an additional number of countries to compile, publish and test your app against during workflows. Note that this setting can be different in NextMajor and NextMinor workflows compared to the CI/CD workflow, by specifying a different value in a workflow settings file. | [ ] |
| keyVaultName | When using Azure KeyVault for the secrets used in your workflows, the KeyVault name needs to be specified in this setting if it isn't specified in the AZURE_CREDENTIALS secret. Read [this](UseAzureKeyVault.md) for more information. | |
| licenseFileUrlSecretName | Specify the name (**NOT the secret itself**) of the LicenseFileUrl secret. Default is LicenseFileUrl. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as LicenseFileUrl when running the CI/CD workflow for AppSource Apps. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | LicenseFileUrl |
| insiderSasTokenSecretName | Specifies the name (**NOT the secret itself**) of the InsiderSasToken secret. Default is InsiderSasToken. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as InsiderSasToken for getting access to Next Minor and Next Major builds. | InsiderSasToken |
| ghTokenWorkflowSecretName | Specifies the name (**NOT the secret itself**) of the GhTokenWorkflow secret. Default is GhTokenWorkflow. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as Personal Access Token with permission to modify workflows when running the Update AL-Go System Files workflow. Read [this](UpdateAlGoSystemFiles.md) for more information. | GhTokenWorkflow |
| adminCenterApiCredentialsSecretName | Specifies the name (**NOT the secret itself**) of the adminCenterApiCredentials secret. Default is adminCenterApiCredentials. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use when connecting to the Admin Center API when creating Online Development Environments. Read [this](CreateOnlineDevEnv2.md) for more information. | AdminCenterApiCredentials |
| installApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of secure URLs, where the CI/CD workflow can download the apps. The apps in installApps are downloaded and installed before compiling and installing the apps. | [ ] |
| installTestApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of secure URLs, where the CI/CD workflow can download the apps. The apps in installTestApps are downloaded and installed before compiling and installing the test apps. Adding a parantheses around the setting indicates that the test in this app will NOT be run, only installed. | [ ] |
| installOnlyReferencedApps | By default, only the apps referenced in the dependency chain of your apps will be installed when inspecting the settings: InstallApps, InstallTestApps and appDependencyProbingPath. If you change this setting to false, all apps found will be installed. | true |
| enableCodeCop | If enableCodeCop is set to true, the CI/CD workflow will enable the CodeCop analyzer when building. | false |
| enableUICop | If enableUICop is set to true, the CI/CD workflow will enable the UICop analyzer when building. | false |
| customCodeCops | CustomCodeCops is an array of paths or URLs to custom Code Cop DLLs you want to enable when building. | [ ] |
| failOn | Specifies what the pipeline will fail on. Allowed values are none, warning and error | error |
| rulesetFile | Filename of the custom ruleset file | |
| keyVaultCertificateUrlSecretName<br />keyVaultCertificatePasswordSecretName<br />keyVaultClientIdSecretName | If you want to enable KeyVault access for your AppSource App, you need to provide 3 secrets as GitHub Secrets or in the Azure KeyVault. The names of those secrets (**NOT the secrets themselves**) should be specified in the settings file with these 3 settings. Default is to not have KeyVault access from your AppSource App. Read [this](EnableKeyVaultForAppSourceApp.md) for more information. | |
| codeSignCertificateUrlSecretName<br />codeSignCertificatePasswordSecretName | When developing AppSource Apps, your app needs to be code signed and you need to add secrets to GitHub secrets or Azure KeyVault, specifying the secure URL from which your codesigning certificate pfx file can be downloaded and the password for this certificate. These settings specifies the names (**NOT the secrets themselves**) of the code signing certificate url and password. Default is to look for secrets called CodeSignCertificateUrl and CodeSignCertificatePassword. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | CodeSignCertificateUrl<br />CodeSignCertificatePassword |
| storageContextSecretName | This setting specifies the name (**NOT the secrets themselves**) of a secret containing a json string with StorageAccountName, ContainerName, BlobName and StorageAccountKey|SasToken. If this secret exists, AL-Go will upload builds to this storage account for every successful build. | StorageContext |
| alwaysBuildAllProjects | This setting only makes sense if the repository is setup for multiple projects.<br />Standard behavior of the CI/CD workflow is to only build the projects, in which files have changes when running the workflow due to a push or a pull request | false |
| skipUpgrade | This setting is used to signal to the pipeline to NOT run upgrade and ignore previous releases of the app. | false |
| cacheImageName | When using self-hosted runners, cacheImageName specifies the prefix for the docker image created for increased performance | my |
| cacheKeepDays | When using self-hosted runners, cacheKeepDays specifies the number of days docker image are cached before cleaned up when running the next pipeline.<br />Note that setting cacheKeepDays to 0 will flush the cache before every build and will cause all other running builds using agents on the same host to fail. | 3 |

## Expert settings (rarely used)

| Name | Description | Default value |
| :-- | :-- | :-- |
| repoName | the name of the repository | name of GitHub repository |
| runNumberOffset | when using **VersioningStrategy** 0, the CI/CD workflow uses the GITHUB RUN_NUMBER as the build part of the version number as described under VersioningStrategy. The RUN_NUMBER is ever increasing and if you want to reset it, when increasing the Major or Minor parts of the version number, you can specify a negative number as runNumberOffset. You can also provide a positive number to get a starting offset. Read about RUN_NUMBER [here](https://docs.github.com/en/actions/learn-github-actions/contexts) | 0 |
| applicationDependency | Application dependency defines the lowest Business Central version supported by your app (Build will fail early if artifacts used are lower than this). The value is calculated by reading app.json for all apps, but cannot be lower than the applicationDependency setting which has a default value of 18.0.0.0 | 18.0.0.0 |
| installTestRunner | Determines whether the test runner will be installed in the pipeline. If there are testFolders in the project, this setting will be true. | calculated |
| installTestFramework | Determines whether the test framework apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test framework apps, this setting will be true | calculated |
| installTestLibraries | Determines whether the test libraries apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test library apps, this setting will be true | calculated |
| installPerformanceToolkit | Determines whether the performance test toolkit apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the performance test toolkit apps, this setting will be true | calculated |
| enableAppSourceCop | Determines whether the AppSourceCop will be enabled in the pipeline. If the project type is AppSource App, then the AppSourceCop will be enabled by default. You can set this value to false to force the AppSourceCop to be disabled | calculated |
| enablePerTenantExtensionCop | Determines whether the PerTenantExtensionCop will be enabled in the pipeline. If the project type is PTE, then the PerTenantExtensionCop will be enabled by default. You can set this value to false to force the PerTenantExtensionCop to be disabled | calculated |
| doNotBuildTests | This setting forces the pipeline to NOT build and run the tests in testFolders | false |
| doNotRunTests | This setting forces the pipeline to NOT run the tests in testFolders. Tests are still being built and published | false |
| memoryLimit | Specifies the memory limit for the build container. By default, this is left to BcContainerHelper to handle and will currently be set to 8G | 8G |

# Expert level

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

## BcContainerHelper settings

The repo settings file (.github\\AL-Go-Settings.json) can contain BcContainerHelper settings. Some BcContainerHelper settings are machine specific (folders and like), and should not be set in the repo settings file.

Settings, which might be relevant to set in the settings file includes

| Setting | Description | Default |
| :-- | :-- | :-- |
| baseUrl | The Base Url for the online Business Central Web Client. This should be changed when targetting embed apps. | https://businesscentral.dynamics.com |
| apiBaseUrl | The Base Url for the online Business Central API endpoint. This should be changed when targetting embed apps. | https://api.businesscentral.dynamics.com |
| PartnerTelemetryConnectionString | The Telemetry Connection String for partner telemetry for DevOps telemetry. | |
| SendExtendedTelemetryToMicrosoft | Set this value to true if you agree to emit extended DevOps telemetry to Microsoft. | false |
| ObjectIdForInternalUse | BcContainerHelper will use this Object ID for internal purposes. Change if the default Object ID is in use. | 88123 |
| TreatWarningsAsErrors | A list of AL warning codes, which should be treated as errors | [ ] |
| DefaultNewContainerParameters | A list of parameters to be added to all container creations in this repo | { } |

## Your own version of AL-Go for GitHub

For experts only, following the description [here](Contributing.md) you can setup a local fork of **AL-Go for GitHub** and use that as your templates. You can fetch upstream changes from Microsoft regularly to incorporate these changes into your version and this way have your modified version of AL-Go for GitHub.

**Note:** Our goal is to never break repositories, which are using AL-Go for GitHub as their template. We almost certainly will break you if you create local modifications to scripts and pipelines.
