# Settings
The behavior of AL-Go for GitHub is very much controlled by the settings in the settings file.

## Where is the settings file located
An AL-Go repository can consist of a single project (with multiple apps) or multiple projects (each with multiple apps). Multiple projects in a single repository are comparable to multiple repositories; they are built, deployed, and tested separately. All apps in each project (single or multiple) are built together in the same pipeline, published and tested together. If a repository is multiple projects, each project is stored in a separate folder in the root of the repository.

When running a workflow or a local script, the settings are applied by reading one or more settings files. Last applied settings file wins. The following lists the settings files and their location:

**.github\\AL-Go-settings.json** is the repository settings file. This settings file contains settings that are relevant for all projects in the repository. If a settings in the repository settings file is found in a subsequent settings file, it will be overridden by the new value.

**Special note:** The repository settings file can also contains `BcContainerHelper` settings, which will be applied when loading `BcContainerHelper` in a workflow.

**.AL-Go\\settings.json** is the project settings file. If the repository is a single project, the .AL-Go folder is in the root folder of the repository. If the repository contains multiple projects, there will be a .AL-Go folder in each project folder.

**.AL-Go\\\<workflow\>.settings.json** is the workflow-specific settings file. This option is rarely used, but if you have special settings, which should only be used for one specific workflow, these settings can be added to a settings file with the name of the workflow followed by `.settings.json`.

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
| templateUrl | Defines the URL of the template repository used to create this project and is used for checking and downloading updates to AL-Go System files. ||
| appDependencyProbingPaths | Array of dependency specifications, from which apps will be downloaded when the CI/CD workflow is starting. Every dependency specification consists of the following properties:<br />**repo** = repository<br />**version** = version<br />**release_status** = release/prerelease/draft<br />**projects** = projects<br />**authtoken** = Auth token<br />**TODO:** complete documentation and add to tests | [ ] |

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| artifact | Determines the artifacts used for building and testing the app.<br />This setting can either be an absolute pointer to Business Central artifacts (https://... - rarely used) or it can be a search specification for artifacts (\<storageaccount\>/\<type\>/\<version\>/\<country\>/\<select\>/\<sastoken\>).<br />If not specified, the artifacts used will be the latest sandbox artifacts from the country specified in the country setting. | |
| companyName | Company name selected in the database, used for running the CI/CD workflow. Default is to use the default company in the selected Business Central localization. | |
| versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 tuples: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app. **Build** and **Revision** are calculated. Currently 3 versioning strategies are supported:<br />**0** = **Build** is the **github [run_number](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the CI/CD workflow, increased by the **runNumberOffset** setting value (if specified). **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**1** = **Build** is the **github [run_id](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the repository. **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**2** = **Build** is the current date  as **yyyyMMdd**. **Revision** is the current time as **hhmmss**. Date and time are always **UTC** timezone to avoid problems during daylight savings time change. Note that if two CI/CD workflows are started within the same second, this could yield to identical version numbers from two differentruns.<br />**+16** use **repoVersion** setting as **appVersion** (**Major** and **Minor**) for all apps | 0 |
| supportedCountries | **TODO:** document | [ ] |
| keyVaultName | **TODO:** document | |
| licenseFileUrlSecretName | **TODO:** document | LicenseFileUrl |
| insiderSasTokenSecretName | **TODO:** document | InsiderSasToken |
| ghTokenWorkflowSecretName | **TODO:** document | GhTokenWorkflow |
| adminCenterApiCredentialsSecretName | **TODO:** document | AdminCenterApiCredentials |
| appDependencies | **TODO:** document | [ ] |
| testDependencies | **TODO:** document | [ ] |
| installApps | **TODO:** document | [ ] |
| installTestApps | **TODO:** document | [ ] |
| enableCodeCop | **TODO:** document | false |
| enableUICop | **TODO:** document | false |
| keyVaultCertificateUrlSecretName | **TODO:** document | |
| keyVaultCertificatePasswordSecretName | **TODO:** document | |
| keyVaultClientIdSecretName | **TODO:** document | |
| codeSignCertificateUrlSecretName | **TODO:** document | CodeSignCertificateUrl |
| codeSignCertificatePasswordSecretName | **TODO:** document | CodeSignCertificatePassword |
| githubRunner | Specifies which github runner will be used for the pipeline, which is the most time consuming task. Currently, you cannot change which runner is used for all the house-keeping tasks. These will always be run on the github hosted runner: windows-latest | windows-latest |
| alwaysBuildAllProjects | This setting only makes sense if the repository is setup for multiple projects.<br />Standard behavior of the CI/CD workflow is to only build the projects, in which files have changes when running the workflow due to a push or a pull request | false |

## Expert settings (rarely used)

| Name | Description | Default value |
| :-- | :-- | :-- |
| repoName | the name of the repository | name of GitHub repository |
| runNumberOffset | **TODO:** document | 0 |
| applicationDependency | **TODO:** document | 19.0.0.0 |
| installTestRunner | Determines wheather the test runner will be installed in the pipeline. If there are testFolders in the project, this setting will be true. | calculated |
| installTestFramework | Determines whether the test framework apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test framework apps, this setting will be true | calculated |
| installTestLibraries | Determines whether the test libraries apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test library apps, this setting will be true | calculated |
| installPerformanceToolkit | Determines whether the performance test toolkit apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the performance test toolkit apps, this setting will be true | calculated |
| enableAppSourceCop | Determines whether the AppSourceCop will be enabled in the pipeline. If the project type is AppSource App, then the AppSourceCop will be enabled by default. You can set this value to false to force the AppSourceCop to be disabled | calculated |
| enablePerTenantExtensionCop | Determines whether the PerTenantExtensionCop will be enabled in the pipeline. If the project type is PTE, then the PerTenantExtensionCop will be enabled by default. You can set this value to false to force the PerTenantExtensionCop to be disabled | calculated |
| doNotBuildTests | This setting forces the pipeline to NOT build and run the tests in testFolders | false |
| doNotRunTests | This setting forces the pipeline to NOT run the tests in testFolders. Tests are still being built and published | false |
| memoryLimit | Specifies the memory limit for the build container. By default, this is left to BcContainerHelper to handle and will currently be set to 8G | 8G |

# Expert level

**TODO:** Describe overrides for Run-AlPipeline
