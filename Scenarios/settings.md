# Settings

The behavior of AL-Go for GitHub is very much controlled by settings and secrets.

To learn more about the secrets used by AL-Go for GitHub, please navigate to [Secrets](secrets.md).

<a id="settings"></a>

## Where are the settings located

Settings can be defined in GitHub variables or in various settings file. An AL-Go repository can consist of a single project (with multiple apps) or multiple projects (each with multiple apps). Settings can be applied on the project level or on the repository level. Multiple projects in a single repository are comparable to multiple repositories; they are built, deployed, and tested separately. All apps in each project (single or multiple) are built together in the same pipeline, published and tested together. If a repository is multiple projects, each project is stored in a separate folder in the root of the repository.

When running a workflow or a local script, the settings are applied by reading settings from GitHub variables and one or more settings files. Last applied settings file wins. The following lists the order of locations to search for settings:

1. `ALGoOrgSettings` is a **GitHub variable**, which can be defined on an **organizational level** and will apply to **all AL-Go repositories** in this organization.

1. `.github/AL-Go-TemplateRepoSettings.doNotEdit.json` is the repository settings from a custom template repository (if applicable)

1. `.github/AL-Go-settings.json` is the **repository settings file**. This settings file contains settings that are relevant for all projects in the repository. **Special note:** The repository settings file can also contains `BcContainerHelper` settings, which will be applied when loading `BcContainerHelper` in a workflow - the GitHub variables are not considered for BcContainerHelper settings. (see expert section).

1. `ALGoRepoSettings` is a **GitHub variable**, which can be defined on an **repository level** and can contain settings that are relevant for **all projects** in the repository.

1. `.github/AL-Go-TemplateProjectSettings.doNotEdit.json` is the project settings from a custom template repository (if applicable)

1. `.AL-Go/settings.json` is the **project settings file**. If the repository is a single project, the .AL-Go folder is in the root folder of the repository. If the repository contains multiple projects, there will be a .AL-Go folder in each project folder (like `project/.AL-Go/settings.json`)

1. `.github/<workflow>.settings.json` is the **workflow-specific settings file** for **all projects**. This option is used for the Current, NextMinor and NextMajor workflows to determine artifacts and build numbers when running these workflows.

1. `.AL-Go/<workflow>.settings.json` is the **workflow-specific settings file** for a **specific project**.

1. `.AL-Go/<username>.settings.json` is the **user-specific settings file**. This option is rarely used, but if you have special settings, which should only be used for one specific user (potentially in the local scripts), these settings can be added to a settings file with the name of the user followed by `.settings.json`.

<a id="basic"></a>

## Basic Project settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="country"></a>country | Specifies which country this app is built against. | us |
| <a id="repoVersion"></a>repoVersion | RepoVersion is the project version number. The Repo Version number consists of \<major>.\<minor> only (unless versioningStrategy is 3, then it should contain \<major>.\<minor>.\<build>) and is used for naming build artifacts in the CI/CD workflow. Build artifacts are named **\<project>-Apps-\<repoVersion>.\<build>.\<revision>** and can contain multiple apps. The Repo Version number is used as major.minor for individual apps if versioningStrategy is +16. | 1.0 |
| <a id="projectName"></a>projectName | Friendly name for an AL-Go project to be used in the UI for various workflows (CICD, Pull Request Build, etc.). If not set, the name for the project will be the relative path from the root of the repository. | '' |
| <a id="appFolders"></a>appFolders | appFolders should be an array of folders (relative to project root), which contains apps for this project. Apps in these folders are sorted based on dependencies and built and published in that order.<br />If appFolders are not specified, AL-Go for GitHub will try to locate appFolders in the root of the project. | [ ] |
| <a id="testFolders"></a>testFolders | testFolders should be an array of folders (relative to project root), which contains test apps for this project. Apps in these folders are sorted based on dependencies and built, published and tests are run in that order.<br />If testFolders are not specified, AL-Go for GitHub will try to locate testFolders in the root of the project. | [ ] |
| <a id="bcptTestFolders"></a>bcptTestFolders | bcptTestFolders should be an array of folders (relative to project root), which contains performance test apps for this project. Apps in these folders are sorted based on dependencies and built, published and bcpt tests are run in that order.<br />If bcptTestFolders are not specified, AL-Go for GitHub will try to locate bcptTestFolders in the root of the project. | [ ] |
| <a id="pageScriptingTests"></a>pageScriptingTests | pageScriptingTests should be an array of page scripting test file specifications, relative to the AL-Go project. Examples of file specifications: `recordings/my*.yml` (for all yaml files in the recordings subfolder matching my\*.yml), `recordings` (for all \*.yml files in the recordings subfolder) or `recordings/test.yml` (for a single yml file) | [ ] |
| <a id="doNotRunpageScriptingTests"></a>doNotRunpageScriptingTests | When true, this setting forces the pipeline to NOT run the page scripting tests specified in pageScriptingTests. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="restoreDatabases"></a>restoreDatabases | restoreDatabases should be an array of events, indicating when you want to start with clean databases in the container. Possible events are: `BeforeBcpTests`, `BeforePageScriptingTests`, `BeforeEachTestApp`, `BeforeEachBcptTestApp`, `BeforeEachPageScriptingTest` | [ ] |
| <a id="appDependencyProbingPaths"></a>appDependencyProbingPaths | Array of dependency specifications, from which apps will be downloaded when the CI/CD workflow is starting. Every dependency specification consists of the following properties:<br />**repo** = repository<br />**version** = version (default latest)<br />**release_status** = latestBuild/release/prerelease/draft (default release)<br />**projects** = projects (default * = all)<br />**branch** = branch (default main)<br />**AuthTokenSecret** = Name of secret containing auth token (default none)<br /> | [ ] |
| <a id="preprocessorSymbols"></a>preprocessorSymbols | List of preprocessor symbols to use when building the apps. This setting can be specified in [workflow specific settings files](https://aka.ms/algosettings#where-are-the-settings-located) or in [conditional settings](https://aka.ms/algosettings#conditional-settings). | [ ] |
| <a id="bcptThresholds"></a>bcptThresholds | Structure with properties for the thresholds when running performance tests using the Business Central Performance Toolkit.<br />**DurationWarning** = a warning is shown if the duration of a bcpt test degrades more than this percentage (default 10)<br />**DurationError** - an error is shown if the duration of a bcpt test degrades more than this percentage (default 25)<br />**NumberOfSqlStmtsWarning** - a warning is shown if the number of SQL statements from a bcpt test increases more than this percentage (default 5)<br />**NumberOfSqlStmtsError** - an error is shown if the number of SQL statements from a bcpt test increases more than this percentage (default 10)<br />*Note that errors and warnings on the build in GitHub are only issued when a threshold is exceeded on the codeunit level, when an individual operation threshold is exceeded, it is only shown in the test results viewer.* |

## AppSource specific basic project settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="appSourceCopMandatoryAffixes"></a>appSourceCopMandatoryAffixes | This setting is only used if the type is AppSource App. The value is an array of affixes, which is used for running AppSource Cop. | [ ] |
| <a id="deliverToAppSource"></a>deliverToAppSource | Structure with properties for AppSource delivery from AL-Go for GitHub. The structure can contain the following properties:<br />**branches** = an array of branch patterns, which are allowed to deliver to AppSource. (Default main)<br />**productId** must be the product Id from partner Center.<br />**mainAppFolder** specifies the appFolder of the main app if you have multiple apps in the same project.<br />**continuousDelivery** can be set to true to enable continuous delivery of every successful build to AppSource Validation. Note that the app will only be in preview in AppSource and you will need to manually press GO LIVE in order for the app to be promoted to production.<br />**includeDependencies** can be set to an array of file names (incl. wildcards) which are the names of the dependencies to include in the AppSource submission. You need to set `generateDependencyArtifact` in the [project settings file](#where-are-the-settings-located) to true in order to include dependencies.<br />**Note:** You will need to define an AppSourceContext secret in order to publish to AppSource. | |
| <a id="obsoleteTagMinAllowedMajorMinor"></a>obsoleteTagMinAllowedMajorMinor | This setting will enable AppSource cop rule AS0105, which causes objects that are pending obsoletion with an obsolete tag version lower than the minimum set in this property are not allowed. | |

## Basic Repository settings

The repository settings are only read from the repository settings file (.github\\AL-Go-Settings.json)

| Name | Description |
| :-- | :-- |
| <a id="type"></a>type | Specifies the type of repository. Allowed values are **PTE** or **AppSource App**. This value comes with the default repository. Default value is PTE. |
| <a id="projects"></a>projects | Specifies the list of projects in this repository (names of folders containing AL-Go projects). If not specified, AL-Go will **enumerate folders in the two levels under the root of the repository** for folders containing a `.AL-Go` folder with a `settings.json` file. |
| <a id="powerPlatformSolutionFolder"></a>powerPlatformSolutionFolder | Contains the name of the folder containing a PowerPlatform Solution (only one) |
| <a id="templateUrl"></a>templateUrl | Defines the URL of the template repository used to create this repository and is used for checking and downloading updates to AL-Go System files. |
| <a id="runs-on"></a>runs-on | Specifies which github runner will be used for all non-build/test jobs in all workflows (except the Update AL-Go System Files workflow). The default is to use the GitHub hosted runner _windows-latest_. After changing the runs-on setting, you need to run Update AL-Go System Files for this to take effect. You can specify a special GitHub Runner for the build job using the GitHubRunner setting. Read [this](SelfHostedGitHubRunner.md) for more information.<br />Setting runs-on to _ubuntu-latest_ will run all non-build/test jobs on Linux, build jobs will still run _windows-latest_ (or whatever you have set in **githubRunner**) |
| <a id="shell"></a>shell | Specifies which shell will be used as the default in all jobs. **powershell** is the default, which results in using _PowerShell 5.1_ (unless you selected _ubuntu-latest_, then **pwsh** is used, which results in using _PowerShell 7_) |
| <a id="githubRunner"></a>githubRunner | Specifies which github runner will be used for the build/test jobs in workflows including a build job. This is the most time consuming task. By default this job uses the _Windows-latest_ github runner (unless overridden by the runs-on setting). This settings takes precedence over runs-on so that you can use different runners for the build job and the housekeeping jobs. See **runs-on** setting. |
| <a id="githubRunnerShell"></a>githubRunnerShell | Specifies which shell is used for build jobs in workflows including a build job. The default is to use the same as defined in **shell**. If the shell setting isn't defined, **powershell** is the default, which results in using _PowerShell 5.1_. Use **pwsh** for _PowerShell 7_. |
| <a id="environments"></a>environments | Array of logical environment names. You can specify environments in GitHub environments or in the repo settings file. If you specify environments in the settings file, you can create your AUTHCONTEXT secret using **\<environmentname>\_AUTHCONTEXT**. You can specify additional information about environments in a setting called **DeployTo\<environmentname>** |
| <a id="deliverto"></a>DeliverTo\<deliveryTarget> | Structure with additional properties for the deliveryTarget specified. Some properties are deliveryTarget specific. The structure can contain the following properties:<br />**Branches** = an array of branch patterns, which are allowed to deliver to this deliveryTarget. (Default main)<br />**CreateContainerIfNotExist** = *[Only for DeliverToStorage]* Create Blob Storage Container if it doesn't already exist. (Default false)<br /> |
| <a id="deployto"></a>DeployTo\<environmentname> | Structure with additional properties for the environment specified. `<environmentName>` refers to the GitHub environment name. The structure can contain the following properties:<br />**EnvironmentType** = specifies the type of environment. The environment type can be used to invoke a custom deployment. (Default SaaS)<br />**EnvironmentName** = specifies the "real" name of the environment if it differs from the GitHub environment.<br />**Branches** = an array of branch patterns, which are allowed to deploy to this environment. These branches can also be defined under the environment in GitHub settings and both settings are honored. If neither setting is defined, the default is the **main** branch only.<br />**Projects** = In multi-project repositories, this property can be a comma separated list of project patterns to deploy to this environment. (Default \*)<br />**DependencyInstallMode** = Determines how dependencies are deployed if `GenerateDependencyArtifact` is true. Default value is `install` to install dependencies if not already installed. Other values are `ignore` for ignoring dependencies and `upgrade` or `forceUpgrade` for upgrading dependencies.<br />**includeTestAppsInSandboxEnvironment** = deploys test apps and their dependencies if the environment type is sandbox (Default is `false`)<br />**excludeAppIds** = array of app ids to exclude from deployment. (Default is `[]`)<br />**Scope** = Determines the mechanism for deployment to the environment (Dev or PTE). If not specified, AL-Go for GitHub will always use the Dev Scope for AppSource Apps, but also for PTEs when deploying to sandbox environments when impersonation (refreshtoken) is used for authentication.<br />**SyncMode** = ForceSync if deployment to this environment should happen with ForceSync, else Add. If deploying to the development endpoint you can also specify Development or Clean. (Default Add)<br />**BuildMode** = specifies which buildMode to use for the deployment. Default is to use the Default buildMode<br />**ContinuousDeployment** = true if this environment should be used for continuous deployment, else false. (Default: AL-Go will continuously deploy to sandbox environments or environments, which doesn't end in (PROD) or (FAT)<br />**runs-on** = specifies which runner to use when deploying to this environment. (Default is settings.runs-on)<br />**shell** = specifies which shell to use when deploying to this environment, pwsh or powershell. (Default is settings.shell)<br />**companyId** = Company Id from Business Central (for PowerPlatform connection)<br />**ppEnvironmentUrl** = Url of the PowerPlatform environment to deploy to<br /> |
| <a id="aldoc"></a>alDoc | Structure with properties for the aldoc reference document generation. The structure can contain the following properties:<br />**continuousDeployment** = Determines if reference documentation will be deployed continuously as part of CI/CD. You can run the **Deploy Reference Documentation** workflow to deploy manually or on a schedule. (Default false)<br />**deployToGitHubPages** = Determines whether or not the reference documentation site should be deployed to GitHub Pages for the repository. In order to deploy to GitHub Pages, GitHub Pages must be enabled and set to GitHub Actuibs. (Default true)<br />**maxReleases** = Maximum number of releases to include in the reference documentation. (Default 3)<br />**groupByProject** = Determines whether projects in multi-project repositories are used as folders in reference documentation<br />**includeProjects** = An array of projects to include in the reference documentation. (Default all)<br />**excludeProjects** = An array of projects to exclude in the reference documentation. (Default none)<br />**header** = Header for the documentation site. (Default: Documentation for...)<br />**footer** = Footer for the documentation site. (Default: Made with...)<br />**defaultIndexMD** = Markdown for the landing page of the documentation site. (Default: Reference documentation...)<br />**defaultReleaseMD** = Markdown for the landing page of the release sites. (Default: Release reference documentation...)<br />*Note that in header, footer, defaultIndexMD and defaultReleaseMD you can use the following placeholders: {REPOSITORY}, {VERSION}, {INDEXTEMPLATERELATIVEPATH}, {RELEASENOTES}* |
| <a id="useProjectDependencies"></a>useProjectDependencies | Determines whether your projects are built using a multi-stage built workflow or single stage. After setting useProjectDependencies to true, you need to run Update AL-Go System Files and your workflows including a build job will change to have multiple build jobs, depending on each other. The number of build jobs will be determined by the dependency depth in your projects.<br />You can change dependencies between your projects, but if the dependency **depth** changes, AL-Go will warn you that updates for your AL-Go System Files are available and you will need to run the workflow. |
| <a id="CICDPushBranches"></a>CICDPushBranches | CICDPushBranches can be specified as an array of branches, which triggers a CI/CD workflow on commit. You need to run the Update AL-Go System Files workflow for the change to take effect.<br />Default is [ "main", "release/\*", "feature/\*" ] |
| <a id="CICDPullrequestBranches"></a>CICDPullRequestBranches | CICDPullRequestBranches can be specified as an array of branches, which triggers a CI/CD workflow on a PR. You need to run the Update AL-Go System Files workflow for the change to take effect.<br />Default is [ "main" ] |
| <a id="pullRequestTrigger"></a>pullRequestTrigger | Setting for specifying the trigger AL-Go should use to trigger Pull Request Builds. You need to run the Update AL-Go System Files workflow for the change to take effect.<BR />Default is [pull_request_target](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request_target) |
| <a id="buildModes"></a>buildModes | A list of build modes to use when building the AL-Go projects. Every AL-Go project will be built using each build mode. The following build modes have special meaning in AL-Go:<br /> **Default**: Apps are compiled as they are in the source code.<br />**Clean**: Should be used for Clean Mode. Use [Conditional Settings](https://aka.ms/algosettings#conditional-settings) with buildMode set the 'Clean' to specify preprocessorSymbols for clean mode.<br />**Translated**: `TranslationFile` compiler feature is enabled when compiling the apps.<br /><br />It is also possible to specify custom build modes by adding a build mode that is different than 'Default', 'Clean' or 'Translated' and use [conditional settings](https://aka.ms/algosettings#conditional-settings) to specify preprocessor symbols and other build settings for the build mode. |
| <a id="useGitSubmodules"></a>useGitSubmodules | If your repository is using Git Submodules, you can set the `useGitSubmodules` setting to `"true"` or `"recursive"` in order to use these submodules during build workflows. If `useGitSubmodules` is not set, git submodules are not initialized. If the submodules reside in private repositories, you need to define a `gitSubmodulesToken` secret. Read [this](https://aka.ms/algosecrets#gitSubmodulesToken) for more information. |
| <a id="commitOptions"></a>commitOptions | If you want more control over how AL-Go creates pull requests or commits changes to the repository you can define `commitOptions`. It is a structure defining how you want AL-Go to handle automated commits or pull requests coming from AL-Go (e.g. for Update AL-Go System Files). The structure contains the following properties:<br />**messageSuffix** = A string you want to append to the end of commits/pull requests created by AL-Go. This can be useful if you are using the Azure Boards integration (or similar integration) to link commits to work items. <br />`createPullRequest` : A boolean defining whether AL-Go should create a pull request or attempt to push directly in the branch.<br />**pullRequestAutoMerge** = A boolean defining whether you want AL-Go pull requests to be set to auto-complete. This will auto-complete the pull requests once all checks are green and all required reviewers have approved.<br />**pullRequestMergeMethod** = A string defining which merge method to use when auto-merging pull requests. Valid values are "merge" and "squash". Default is "squash".<br />**pullRequestLabels** = A list of labels to add to the pull request. The labels need to be created in the repository before they can be applied.<br />If you want different behavior in different AL-Go workflows you can add the `commitOptions` setting to your [workflow-specific settings files](https://github.com/microsoft/AL-Go/blob/main/Scenarios/settings.md#where-are-the-settings-located). |
| <a id="incrementalBuilds"></a>incrementalBuilds | A structure defining how you want AL-Go to handle incremental builds. When using incremental builds for a build, AL-Go will look for the latest successful CI/CD build, newer than the defined `retentionDays` and only rebuild projects or apps (based on `mode`) which needs to be rebuilt. The structure supports the following properties:<br />**onPush** = Determines whether incremental builds is enabled in CI/CD triggered by a merge/push event. Default is **false**.<br />**onPull_Request** = Determines whether incremental builds is enabled in Pull Requests. Default is **true**.<br />**onSchedule** = Determines whether incremental builds is enabled in CI/CD when running on a schedule. Default is **false**.<br />**retentionDays** = Number of days a successful build is good (and can be used for incremental builds). Default is **30**.<br />**mode** = Specifies the mode for incremental builds. Currently, two values are supported. Use **modifiedProjects** when you want to rebuild all apps in all modified projects and depending projects or **modifiedApps** if you want to rebuild modified apps and all apps with dependencies to this app.<br />**NOTE:** when running incremental builds, it is recommended to also set `workflowConcurrency` for the CI/CD workflow, as defined [here](https://aka.ms/algosettings#workflowConcurrency). |
| <a id="workflowDefaultInputs"></a>workflowDefaultInputs | An array of workflow input default values. This setting allows you to configure default values for workflow_dispatch inputs, making it easier to run workflows manually with consistent settings. Each entry should contain:<br />  **name** = The name of the workflow input<br />  **value** = The default value (can be string, boolean, or number)<br />**Important validation rules:**<br />  • The value type must match the input type defined in the workflow YAML file (boolean, number, string, or choice)<br />  • For choice inputs, the value must be one of the options declared in the workflow<br />  • Choice validation is case-sensitive<br />Type and choice validation is performed when running the "Update AL-Go System Files" workflow to prevent configuration errors.<br />When you run the "Update AL-Go System Files" workflow, these default values will be applied to all workflows that have matching input names.<br />**Usage:** This setting can be used on its own in repository settings to apply defaults to all workflows with matching input names. Alternatively, you can use it within [conditional settings](#conditional-settings) to apply defaults only to specific workflows, branches, or other conditions.<br />**Important:** When multiple conditional settings blocks match and both define `workflowDefaultInputs`, the arrays are merged (all entries are kept). When the defaults are applied to workflows, the last matching entry for each input name wins.<br />**Example:**<br />`"workflowDefaultInputs": [`<br />`  { "name": "directCommit", "value": true },`<br />`  { "name": "useGhTokenWorkflow", "value": true },`<br />`  { "name": "updateVersionNumber", "value": "+0.1" }`<br />`]` |

<a id="advanced"></a>

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="artifact"></a>artifact | Determines the artifacts used for building and testing the app.<br />This setting can either be an absolute pointer to Business Central artifacts (https://... - rarely used) or it can be a search specification for artifacts (\<storageaccount>/\<type>/\<version>/\<country>/\<select>).<br />If not specified, the artifacts used will be the latest sandbox artifacts from the country specified in the country setting.<br />**Note:** if version is set to `*`, then the application dependency from the apps in your project will determine which artifacts to use. If select is *first*, then you will get the first artifacts matching your application dependency. If select is *latest* then you will get the latest artifacts with the same major.minor as your application dependency. | |
| <a id="updateDependencies"></a>updateDependencies | Setting updateDependencies to true causes AL-Go to build your app against the first compatible Business Central build and set the dependency version numbers in the app.json accordingly during build. All version numbers in the built app will be set to the version number used during compilation. <br />⚠️ **Warning:** When the `updateDependencies` setting is enabled, the application versions from the BC Artifact are stamped into the `app.json`. However, not all app versions available in BC Artifacts are shipped in BC SaaS, which can lead to dependency resolution failures during AppSource validation. Therefore, it is not recommended to use this setting if you intend on deploying the build to AppSource. | false |
| <a id="generateDependencyArtifact"></a>generateDependencyArtifact | When this repository setting is true, CI/CD pipeline generates an artifact with the external dependencies used for building the apps in this repo. | false |
| <a id="companyName"></a>companyName | Company name selected in the database, used for running the CI/CD workflow. Default is to use the default company in the selected Business Central localization. | |
| <a id="versioningStrategy"></a>versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 segments: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app. **Build** and **Revision** are calculated. Currently 3 versioning strategies are supported:<br />**0** = **Build** is the **github [run_number](https://go.microsoft.com/fwlink/?linkid=2217416&clcid=0x409)** for the CI/CD workflow, increased by the **runNumberOffset** setting value (if specified). **Revision** is the **github [run_attempt](https://go.microsoft.com/fwlink/?linkid=2217416&clcid=0x409)** subtracted 1.<br />**2** = **Build** is the current date as **yyyyMMdd**. **Revision** is the current time as **hhmmss**. Date and time are always **UTC** timezone to avoid problems during daylight savings time change. Note that if two CI/CD workflows are started within the same second, this could yield to identical version numbers from two different runs.<br />**3** = **Build** is taken from **app.json** (like Major and Minor) and **Revision** is the **github [run_number](https://go.microsoft.com/fwlink/?linkid=2217416&clcid=0x409)** of the workflow run<br />**15** = **Build** is max value and **Revision** is the **github [run_number](https://go.microsoft.com/fwlink/?linkid=2217416&clcid=0x409)** of the workflow run. **Note**: use this strategy with caution. We recommend using it only when producing non-official artifacts (e.g. from PR builds or test workflows).<br /><br />**+16** when adding 16 to the above versioningStrategies, all builds will use **repoVersion** setting instead of the *Major.Minor* found inside app.json (and also *build* if versioningStrategy is 3+16) | 0 |
| <a id="additionalCountries"></a>additionalCountries | This property can be set to an additional number of countries to compile, publish and test your app against during workflows. Note that this setting can be different in NextMajor and NextMinor workflows compared to the CI/CD workflow, by specifying a different value in a workflow settings file. | [ ] |
| <a id="keyVaultName"></a>keyVaultName | When using Azure KeyVault for the secrets used in your workflows, the KeyVault name needs to be specified in this setting if it isn't specified in the AZURE_CREDENTIALS secret. Read [this](UseAzureKeyVault.md) for more information. | |
| <a id="licenseFileUrlSecretName"></a>licenseFileUrlSecretName | Specify the name (**NOT the secret**) of the LicenseFileUrl secret. Default is LicenseFileUrl. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as LicenseFileUrl. A LicenseFileUrl is required when building AppSource apps for Business Central prior to version 22. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | LicenseFileUrl |
| <a id="ghTokenWorkflowSecretName"></a>ghTokenWorkflowSecretName | Specifies the name (**NOT the secret**) of the GhTokenWorkflow secret. Default is GhTokenWorkflow. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as Personal Access Token with permission to modify workflows when running the Update AL-Go System Files workflow. Read [this](UpdateAlGoSystemFiles.md) for more information. | GhTokenWorkflow |
| <a id="adminCenterApiCredentialsSecretName"></a>adminCenterApiCredentialsSecretName | Specifies the name (**NOT the secret**) of the adminCenterApiCredentials secret. Default is adminCenterApiCredentials. AL-Go for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use when connecting to the Admin Center API when creating Online Development Environments. Read [this](CreateOnlineDevEnv2.md) for more information. | AdminCenterApiCredentials |
| <a id="installApps"></a>installApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installApps are downloaded and installed before compiling and installing the apps.<br/>**Note:** If you specify ${{SECRETNAME}} as part of a URL, it will be replaced by the value of the secret SECRETNAME. | [ ] |
| <a id="installTestApps"></a>installTestApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installTestApps are downloaded and installed before compiling and installing the test apps. Adding a parentheses around the setting indicates that the test in this app will NOT be run, only installed.<br/>**Note:** If you specify ${{SECRETNAME}} as part of a URL, it will be replaced by the value of the secret SECRETNAME. | [ ] |
| <a id="configPackages"></a>configPackages | An array of configuration packages to be applied to the build container before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="configPackages.country"></a>configPackages.country | An array of configuration packages to be applied to the build container for country **country** before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="installOnlyReferencedApps"></a>installOnlyReferencedApps | By default, only the apps referenced in the dependency chain of your apps will be installed when inspecting the settings: InstallApps, InstallTestApps and appDependencyProbingPath. If you change this setting to false, all apps found will be installed. | true |
| <a id="enableCodeCop"></a>enableCodeCop | If enableCodeCop is set to true, the CI/CD workflow will enable the CodeCop analyzer when building. | false |
| <a id="enableUICop"></a>enableUICop | If enableUICop is set to true, the CI/CD workflow will enable the UICop analyzer when building. | false |
| <a id="customCodeCops"></a>customCodeCops | CustomCodeCops is an array of paths or URLs to custom Code Cop DLLs you want to enable when building. | [ ] |
| <a id="enableCodeAnalyzersOnTestApps"></a>enableCodeAnalyzersOnTestApps | If enableCodeAnalyzersOnTestApps is set to true, the code analyzers will be enabled when building test apps as well. | false |
| <a id="trackALAlertsInGitHub"></a>trackALAlertsInGitHub | If trackALAlertsInGitHub is set to true, AL code analysis results will be uploaded and tracked in the GitHub security tab. Additionally, if Advanced Security is enabled in the repo, new AL code alerts will be posted in PRs that introduce them. This setting must be enabled on the repo level, but can be optionally disabled per project. <br> **Note:** AL Alerts are only enabled for warnings at the moment. Support for displaying errors will come in a future release | false |
| <a id="failOn"></a>failOn | Specifies what the pipeline will fail on. Allowed values are none, warning, newWarning and error. Using 'newWarning' will lead to pull requests failing if new warnings are added, while still behaving like 'error' for normal build steps. | error |
| <a id="rulesetFile"></a>rulesetFile | Filename of the custom ruleset file | |
| <a id="enableExternalRulesets"></a>enableExternalRulesets | If enableExternalRulesets is set to true, then you can have external rule references in the ruleset | false |
| <a id="vsixFile"></a>vsixFile | Determines which version of the AL Language Extension to use for building the apps. This can be:<br />**default** to use the AL Language Extension which ships with the Business Central version you are building for<br />**latest** to always download the latest AL Language Extension from the marketplace<br />**preview** to always download the preview AL Language Extension from the marketplace.<br/>or a **direct download URL** pointing to the AL Language VSIX file to use for building the apps.<br />By default, AL-Go uses the AL Language extension, which is shipped with the artifacts used for the build. | default |
| <a id="codeSignCertificateUrlSecretName"></a>codeSignCertificateUrlSecretName<br />codeSignCertificatePasswordSecretName | When developing AppSource Apps, your app needs to be code signed.<br/>**Note** there is a new way of signing apps, which is described [here](../Scenarios/Codesigning.md).<br />Using the old mechanism, you need a certificate .pfx file and password and you need to add secrets to GitHub secrets or Azure KeyVault, specifying the secure URL from which your codesigning certificate pfx file can be downloaded and the password for this certificate. These settings specifies the names (**NOT the secrets**) of the code signing certificate url and password. Default is to look for secrets called CodeSignCertificateUrl and CodeSignCertificatePassword. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | CodeSignCertificateUrl<br />CodeSignCertificatePassword |
| <a id="keyVaultCodesignCertificateName"></a>keyVaultCodesignCertificateName | When developing AppSource Apps, your app needs to be code signed.<br/>Name of a certificate stored in your KeyVault that can be used to codesigning. To use this setting you will also need enable Azure KeyVault in your AL-Go project. Read [this](UseAzureKeyVault.md) for more information | |
| <a id="applicationInsightsConnectionStringSecretName"></a>applicationInsightsConnectionStringSecretName | This setting specifies the name (**NOT the secret**) of a secret containing the application insights connection string for the apps. | applicationInsightsConnectionString |
| <a id="storageContextSecretName"></a>storageContextSecretName | This setting specifies the name (**NOT the secret**) of a secret containing a json string with StorageAccountName, ContainerName, BlobName and StorageAccountKey or SAS Token. If this secret exists, AL-Go will upload builds to this storage account for every successful build.<br />The BcContainerHelper function New-ALGoStorageContext can create a .json structure with this content. | StorageContext |
| <a id="alwaysBuildAllProjects"></a>alwaysBuildAllProjects (**deprecated**) | This setting only makes sense if the repository is setup for multiple projects.<br />Standard behavior of the CI/CD workflow is to only build the projects, in which files have changes when running the workflow due to a push or a pull request | false |
| <a id="fullBuildPatterns"></a>fullBuildPatterns | Use this setting to list important files and folders. Changes to any of these files and folders would trigger a full Pull Request build (all AL-Go projects will be built). <br /> *Examples*:<br /> 1. Specifying `fullBuildPatterns` as `[ "Build/*" ]` means that any changes from a PR to the `Build` folder would trigger a full build. <br /> 2. Specifying `fullBuildPatterns` as `[ "*" ]` means that any changes from a PR would trigger a full build and it is equivalent to setting `alwaysBuildAllProjects` to `true`. | [ ] |
| <a id="skipUpgrade"></a>skipUpgrade | This setting is used to signal to the pipeline to NOT run upgrade and ignore previous releases of the app. | false |
| <a id="cacheImageName"></a>cacheImageName | When using self-hosted runners, cacheImageName specifies the prefix for the docker image created for increased performance | my |
| <a id="cacheKeepDays"></a>cacheKeepDays | When using self-hosted runners, cacheKeepDays specifies the number of days docker image are cached before cleaned up when running the next pipeline.<br />Note that setting cacheKeepDays to 0 will flush the cache before every build and will cause all other running builds using agents on the same host to fail. | 3 |
| <a id="assignPremiumPlan"></a>assignPremiumPlan | Setting assignPremiumPlan to true in your project setting file, causes the build container to be created with the AssignPremiumPlan set. This causes the auto-created user to have Premium Plan enabled. This setting is needed if your tests require premium plan enabled. | false |
| <a id="enableTaskScheduler"></a>enableTaskScheduler | Setting enableTaskScheduler to true in your project setting file, causes the build container to be created with the Task Scheduler running. | false |
| <a id="useCompilerFolder"></a>useCompilerFolder | Setting useCompilerFolder to true causes your pipelines to use containerless compiling. Unless you also set **doNotPublishApps** to true, setting useCompilerFolder to true won't give you any performance advantage, since AL-Go for GitHub will still need to create a container in order to publish and test the apps. In the future, publishing and testing will be split from building and there will be other options for getting an instance of Business Central for publishing and testing. **Note** when using UseCompilerFolder you need to sign apps using the new signing mechanism described [here](../Scenarios/Codesigning.md). | false |
| <a id="excludeEnvironments"></a>excludeEnvironments | excludeEnvironments can be an array of GitHub Environments, which should be excluded from the list of environments considered for deployment. github-pages is automatically added to this array and cannot be used as environment for deployment of AL-Go for GitHub projects. | [ ] |
| <a id="trustMicrosoftNuGetFeeds"></a>trustMicrosoftNuGetFeeds | Unless this setting is set to false, AL-Go for GitHub will trust the NuGet feeds provided by Microsoft. The feeds provided by Microsoft contains all Microsoft apps, all Microsoft symbols and symbols for all AppSource apps. | true |
| <a id="trustedNuGetFeeds"></a>trustedNuGetFeeds | trustedNuGetFeeds can be an array of NuGet feed specifications, which AL-Go for GitHub will use for dependency resolution. Every feed specification must include a URL property and can optionally include a few other properties:<br />**url** = The URL of the feed (examples: https://pkgs.dev.azure.com/myorg/apps/\_packaging/myrepo/nuget/v3/index.json or https://nuget.pkg.github.com/mygithuborg/index.json").<br />**authTokenSecret** = If the NuGet feed specified by URL is private, the authTokenSecret must be the name of a secret containing the authentication token with permissions to search and read packages from the NuGet feed.<br />**patterns** = AL-Go for GitHub will only trust packages, where the ID matches this pattern. Default is all packages (\*).<br />**fingerprints** = If specified, AL-Go for GitHub will only trust packages signed with a certificate with a fingerprint matching one of the fingerprints in this array. | [ ] |
| <a id="nuGetFeedSelectMode"></a>nuGetFeedSelectMode | Determines the select mode when finding Business Central app packages from NuGet feeds, based on the dependency version specified in app.json. Options are:<br/>- `Earliest` for earliest version of the package<br/>- `EarliestMatching` for earliest version of the package also compatible with the Business Central version used<br/>- `Exact` for the exact version of the package<br/>- `Latest` for the latest version of the package<br/>- `LatestMatching` for the latest version of the package also compatible with the Business Central version used. | LatestMatching |
| <a id="trustedSigning"></a>trustedSigning | Structure defining the properties needed for enabling trusted Signing. Please read [this](https://learn.microsoft.com/en-us/azure/trusted-signing/) to setup your Azure Trusted Signing Account and Certificate Profile and then provide these properties in this setting:<br />**Account** must be the name of your trusted signing account.<br />**Endpoint** must point to the endpoint of your trusted signing account (ex. https://weu.codesigning.azure.net).<br />**CertificateProfile** must be the CertificateProfile in your trusted signing account you want to use for signing.<br />Please note that your Azure_Credentials secret (Microsoft Entra ID App or Managed identity) needs to provide access to your azure subscription and be assigned the `Trusted Signing Certificate Profile Signer` role in the Trusted Signing Account. |
| <a id="shortLivedArtifactsRetentionDays"></a>shortLivedArtifactsRetentionDays | Number of days to keep short lived build artifacts (f.ex build artifacts from pull request builds, next minor or next major builds). 0 means use GitHub default. | 1 |
| <a id="updateALGoSystemFilesEnvironment"></a>updateALGoSystemFilesEnvironment | If specified, this is the name of the environment, which holds the GhTokenWorkflow secret. With this, you can ensure that the Update AL-Go System Files can be guarded by an approval workflow by setting this on the environment used. You need to run the Update AL-Go System Files (with the GhTokenWorkflow in place globally) this setting to take effect. | |

## Workflow specific settings

The following settings are only allowed in workflow specific settings files or in conditional settings, specifying the workflows for which is should be enabled. The workflow specific settings file can be created in `.github\\<workflowName>.settings.json`

| Name | Description |
| :-- | :-- |
| <a id="workflowSchedule"></a>workflowSchedule | The value should be a structure with a property named `cron`, containing a valid crontab, which is the CRON schedule for when the specified workflow should run. Default is no scheduled runs, only manual triggers. Build your crontab string here: [https://crontab.guru](https://crontab.guru). You need to run the Update AL-Go System Files workflow for the schedule to take effect.<br/> The structure can also contain `includeBranches`, an array of branches to support when running the workflow on multiple branches. Currently, only "Update AL-Go System Files" is supported to run on multiple branches. **Note:** If you configure a WorkflowSchedule for the CI/CD workflow, AL-Go will stop triggering CICDs on push unless you have also added CICDPushBranches to your settings.<br/>**Note also:** If you define a schedule for Update AL-Go System Files, it uses direct Commit instead of creating a PR. |
| <a id="workflowConcurrency"></a>workflowConcurrency | A setting to control concurrency of workflows. Like with the `WorkflowSchedule` setting, this setting should be applied in workflow specific settings files or conditional settings. By default, all workflows allows for concurrency, except for the Create Release workflow. If you are using incremental builds in CI/CD it is also recommented to set WorkflowConcurrency to:<br/>`[ "group: ${{ github.workflow }}-${{ github.ref }}", "cancel-in-progress: true" ]`<br />in order to cancel prior incremental builds on the same branch.<br />Read more about workflow concurrency [here](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs).

## AppSource specific advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id=""></a>appSourceContextSecretName | This setting specifies the name (**NOT the secret**) of a secret containing a json string with ClientID, TenantID and ClientSecret or RefreshToken. If this secret exists, AL-Go will can upload builds to AppSource validation. | AppSourceContext |
| <a id=""></a>keyVaultCertificateUrlSecretName<br />keyVaultCertificatePasswordSecretName<br />keyVaultClientIdSecretName | If you want to enable KeyVault access for your AppSource App, you need to provide 3 secrets as GitHub Secrets or in the Azure KeyVault. The names of those secrets (**NOT the secrets**) should be specified in the settings file with these 3 settings. Default is to not have KeyVault access from your AppSource App. Read [this](EnableKeyVaultForAppSourceApp.md) for more information. | |

<a id="conditional"></a>

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

to your [project settings file](#where-are-the-settings-located) will ensure that all branches matching the patterns in branches will use doNotPublishApps=true and doNotSignApps=true during CI/CD. Conditions can be:

- **repositories** settings will be applied to repositories matching the patterns
- **projects** settings will be applied to projects matching the patterns
- **buildModes** settings will be applied when building with these buildModes
- **branches** settings will be applied to branches matching the patterns
- **workflows** settings will be applied to workflows matching the patterns
- **users** settings will be applied for users matching the patterns

**Note:** You can use `workflowDefaultInputs` within conditional settings to apply workflow input defaults only when certain conditions are met. For example, you could set different default values for specific workflows or branches.

You could imagine that you could have an organizational settings variable containing:

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

> [!NOTE]
> You can have conditional settings on any level and all conditional settings which has all conditions met will be applied in the order of settings file + appearance.

<a id="workflow-name-sanitization"></a>

### Workflow Name Sanitization

When matching workflow names for conditional settings, AL-Go sanitizes the actual workflow name before comparison. Sanitization removes invalid filename characters such as leading spaces, quotes, colons, slashes, and other special characters. For example, a workflow named `" CI/CD"` would be sanitized to `"CICD"` for matching purposes.

<a id="expert"></a>

# Expert level

The settings and functionality in the expert section might require knowledge about GitHub Workflows/Actions, YAML, docker and PowerShell. Please only change these settings and use this functionality after careful consideration as these things might change in the future and will require you to modify the functionality you added based on this.

Please read the release notes carefully when installing new versions of AL-Go for GitHub.

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
| <a id="doNotRunTests"></a>doNotRunTests | This setting forces the pipeline to NOT run the tests in testFolders. Tests are still being built and published. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="doNotRunBcptTests"></a>doNotRunBcptTests | This setting forces the pipeline to NOT run the performance tests in testFolders. Performance tests are still being built and published. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="memoryLimit"></a>memoryLimit | Specifies the memory limit for the build container. By default, this is left to BcContainerHelper to handle and will currently be set to 8G | 8G |
| <a id="BcContainerHelperVersion"></a>BcContainerHelperVersion | This setting can be set to a specific version (ex. 3.0.8) of BcContainerHelper to force AL-Go to use this version. **latest** means that AL-Go will use the latest released version. **preview** means that AL-Go will use the latest preview version. **dev** means that AL-Go will use the dev branch of containerhelper. | latest (or preview for AL-Go preview) |
| <a id="unusedALGoSystemFiles"></a>unusedALGoSystemFiles (**deprecated**) | An array of AL-Go System Files, which won't be updated during Update AL-Go System Files. They will instead be removed.<br />Use this setting with care, as this can break the AL-Go for GitHub functionality and potentially leave your repo no longer functional. | [ ] |
| <a id="reportsuppresseddiagnostics"></a>reportSuppressedDiagnostics | If this setting is set to true, the AL compiler will report diagnostics which are suppressed in the code using the pragma `#pragma warning disable <id>`. This can be useful if you want to ensure that no warnings are suppressed in your code. | false |
| <a id="customALGoFiles"></a>customALGoFiles | An object to configure custom AL-Go files, that will be updated during "Update AL-Go System Files" workflow. The object can contain properties `filesToInclude` and `filesToExclude`. Read more at [Customizing AL-Go](CustomizingALGoForGitHub.md#Using-custom-template-files). | `{ "filesToInclude": [], "filesToExclude": [] }`

## Overwrite settings <a id="overwriteSettings"></a>

By default, AL-Go merges settings from various places (see [settings levels](#where-are-the-settings-located)).

Basic setting types such as `string` and `integer` are _overwritten_, but settings with complex types such as `array` and `object` are _merged_.

_Example_:
Say, `ALGoOrgSettings` contains the following values

```json
{
    "country": "de"
    "buildModes": ["Default"]
}
```

and `.github\AL-Go-Settings.json` contains the following values:

```json
{
    "country": "dk"
    "buildModes": ["Clean"]
}
```

then, after merging, the result settings object will contain the following values:

```json
{
    "country": "dk"
    "buildModes": ["Default", "Clean"]
}
```

In order to change this behavior, you can specify `overwriteSettings` property on a settings object. The purpose of the property is to list settings, for which the value will be overwritten, instead of merged.

_Example_:
Say, `ALGoOrgSettings` contains the following values:

```json
{
    "country": "de"
    "buildModes": ["Default"]
}
```

and `.github\AL-Go-Settings.json` contains the following values

```json
{
    "overwriteSettings": ["buildModes"]
    "country": "dk"
    "buildModes": ["Clean"]
}
```

then, after merging, the result settings object will contain the following values:

```json
{
    "country": "dk"
    "buildModes": ["Clean"]
}
```

> _**Note**_: `overwriteSettings` isn't a setting on its own and it isn't available in the output of `ReadSetting` action, for example. It's merely used to control the settings merging mechanism and allow overwriting complex settings types. The value of `overwriteSettings` should only contain settings of types _array_ or _object_ and all the settings in `overwriteSettings` should be present with the new value.

<a id="customdelivery"></a>

## Custom Delivery

You can override existing AL-Go Delivery functionality or you can define your own custom delivery mechanism for AL-Go for GitHub, by specifying a PowerShell script named `DeliverTo<DeliveryTarget>.ps1` in the .github folder. The following example will spin up a delivery job to SharePoint on CI/CD and Release. Beside the script, you also need to create a secret called `<DeliveryTarget>Context`, formatted as compressed json, containing delivery information for your delivery target.

### DeliverToSharePoint.ps1

```powershell
Param(
    [Hashtable]$parameters
)

Write-Host "Current project path: $($parameters.project)"
Write-Host "Current project name: $($parameters.projectName)"
Write-Host "Delivery Type (CD or Release): $($parameters.type)"
Write-Host "Delivery Context: $($parameters.context)"
Write-Host "Folder containing apps: $($parameters.appsFolder)"
Write-Host "Folder containing test apps: $($parameters.testAppsFolder)"
Write-Host "Folder containing dependencies (requires generateDependencyArtifact set to true): $($parameters.dependenciesFolder)"

Write-Host "Repository settings:"
$parameters.RepoSettings | Out-Host
Write-Host "Project settings:"
$parameters.ProjectSettings | Out-Host
```

> [!NOTE]
> You can override existing AL-Go for GitHub delivery functionality by creating a script called f.ex. DeliverToStorage.ps1 in the .github folder.

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

<a id="customdeployment"></a>

## Custom Deployment

You can override existing AL-Go Deployment functionality or you can define your own custom deployment mechanism for AL-Go for GitHub. By specifying a PowerShell script named `DeployTo<EnvironmentType>.ps1` in the .github folder. Default Environment Type is SaaS, but you can define your own type by specifying EnvironmentType in the `DeployTo<EnvironmentName>` setting. The following example will create a script, which would be called by CI/CD and Publish To Environment, when EnvironmentType is set to OnPrem.

### DeployToOnPrem.ps1

```powershell
Param(
    [Hashtable]$parameters
)

Write-Host "Deployment Type (CD or Release): $($parameters.type)"
Write-Host "Apps to deploy: $($parameters.apps)"
Write-Host "Environment Type: $($parameters.EnvironmentType)"
Write-Host "Environment Name: $($parameters.EnvironmentName)"

$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempPath | Out-Null
Copy-AppFilesToFolder -appFiles $parameters.apps -folder $tempPath | Out-Null
$appsList = @(Get-ChildItem -Path $tempPath -Filter *.app)
if (-not $appsList -or $appsList.Count -eq 0) {
    Write-Host "::error::No apps to publish found."
    exit 1
}
Write-Host "Apps:"
$appsList | ForEach-Object { Write-Host "- $($_.Name)" }
```

> [!NOTE]
> You can override existing AL-Go for GitHub deployment functionality by creating a script called f.ex. DeployToSaas.ps1 in the .github folder, as the default deployment type is Saas.

Here are the parameters to use in your custom script:

| Parameter | Description | Example |
| --------- | :--- | :--- |
| `$parameters.type` | Type of delivery (CD or Release) | CD |
| `$parameters.apps` | Apps to deploy. This can either be an array of .zip files or .app files, or it can be an array of folders, containing apps or .zip files. Publish-BcContainerApp supports this array directly, but you should use `Copy-AppFilesToFolder -appFiles $parameters.apps -folder $tempFolder` to extract and copy all apps to a temp folder, if you are to handle the apps yourself. | /home/runner/.../GHP-Common-main-Apps-2.0.33.0.zip |
| `$parameters.EnvironmentType` | Environment type | SaaS |
| `$parameters.EnvironmentName` | Environment name | Production |
| `$parameters.Branches` | Branches which should deploy to this environment (from settings) | main,dev |
| `$parameters.AuthContext` | AuthContext in a compressed Json structure | {"refreshToken":"mytoken"} |
| `$parameters.BranchesFromPolicy` | Branches which should deploy to this environment (from GitHub environments) | main |
| `$parameters.Projects` | Projects to deploy to this environment | |
| `$parameters.Scope` | Identifies the scope for the deployment, Dev or PTE | PTE |
| `$parameters.SyncMode` | Is the SyncMode to use for the deployment: ForceSync or Add. If deploying to the dev scope, it can also be Development or Clean | Add |
| `$parameters.BuildMode` | Is the buildMode used for the deployment | Clean |
| `$parameters.ContinuousDeployment` | Is this environment setup for continuous deployment | false |
| `$parameters."runs-on"` | GitHub runner to be used to run the deployment script | windows-latest |
| `$parameters."shell"` | Shell used to run the deployment script, pwsh or powershell | powershell |

<a id="scriptoverrides"></a>

## Run-AlPipeline script override

AL-Go for GitHub utilizes the Run-AlPipeline function from BcContainerHelper to perform the actual build (compile, publish, test etc). The Run-AlPipeline function supports overriding functions for creating containers, compiling apps and a lot of other things.

This functionality is also available in AL-Go for GitHub, by adding a file to the .AL-Go folder, you automatically override the function.

Note that changes to AL-Go for GitHub or Run-AlPipeline functionality in the future might break the usage of these overrides.

| Override | Description |
| :-- | :-- |
| PipelineInitialize.ps1 | Initialize the pipeline |
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
| BackupBcContainerDatabases | Backup Databases in container for subsequent restore(s) |
| RestoreDatabasesInBcContainer | Restore Databases in container |
| PreCompileApp | Custom script to run _before_ compiling an app. The script should accept the type of the app (`[string] $appType`) and a reference to the compilation parameters (`[ref] $compilationParams`).<br/>Possible values for `$appType` are: _app_, _testApp_, _bcptApp_.
| PostCompileApp | Custom script to run _after_ compiling an app. The script should accept the file path of the produced .app file (`[string] $appFilePath`), the type of the app (`[string] $appType`), and a hashtable of the compilation parameters (`[hashtable] $compilationParams`).<br/>Possible values for `$appType` are: _app_, _testApp_, _bcptApp_.
| InstallMissingDependencies | Install missing dependencies |
| PipelineFinalize.ps1 | Finalize the pipeline |

## BcContainerHelper settings

The repo settings file (.github\\AL-Go-Settings.json) can contain BcContainerHelper settings. Some BcContainerHelper settings are machine specific (folders and like), and should not be set in the repo settings file.

Settings, which might be relevant to set in the settings file includes

Note that changes to AL-Go for GitHub or Run-AlPipeline functionality in the future might break the usage of these overrides.

| Setting | Description | Default |
| :-- | :-- | :-- |
| baseUrl | The Base Url for the online Business Central Web Client. This should be changed when targetting embed apps. | [https://businesscentral.dynamics.com](https://businesscentral.dynamics.com) |
| apiBaseUrl | The Base Url for the online Business Central API endpoint. This should be changed when targetting embed apps. | [https://api.businesscentral.dynamics.com](https://api.businesscentral.dynamics.com) |
| PartnerTelemetryConnectionString | The Telemetry Connection String for partner telemetry for DevOps telemetry. | |
| SendExtendedTelemetryToMicrosoft | Set this value to true if you agree to emit extended DevOps telemetry to Microsoft. | false |
| ObjectIdForInternalUse | BcContainerHelper will use this Object ID for internal purposes. Change if the default Object ID is in use. | 88123 |
| TreatWarningsAsErrors | A list of AL warning codes, which should be treated as errors | [ ] |
| DefaultNewContainerParameters | A list of parameters to be added to all container creations in this repo | { } |

<a id="customjobs"></a>

## Custom jobs in AL-Go for GitHub workflows

Adding a custom job to any AL-Go for GitHub workflow is done by adding a job with the name `CustomJob<something>` to the end of an AL-Go for GitHub workflow, like this:

```
  CustomJob-PrepareDeploy:
    name: My Job
    needs: [ Build ]
    runs-on: [ ubuntu-latest ]
    defaults:
      run:
        shell: pwsh
    steps:
      - name: This is my job
        run: |
          Write-Host "This is my job"
```

In the `needs` property, you specify which jobs should be complete before this job is run. If you require this job to run before other AL-Go for GitHub jobs are complete, you can add the name of this job in the `needs` property of that job, like:

```
  Deploy:
    needs: [ Initialization, Build, CustomJob-PrepareDeploy ]
    if: always() && needs.Build.result == 'Success' && needs.Initialization.outputs.environmentCount > 0
    strategy: ${{ fromJson(needs.Initialization.outputs.environmentsMatrixJson) }}
```

Custom jobs will be preserved when running Update AL-Go System Files.

**Note** that installing [apps from the GitHub marketplace](https://github.com/marketplace?type=apps) might require you to add custom jobs or steps to some of the workflows to get the right integration. In custom jobs, you can use any [actions from the GitHub marketplace](https://github.com/marketplace?type=actions).

<a id="customtemplate"></a>

## Custom template repositories

If you are utilizing script overrides, custom jobs, custom delivery or like in many repositories, you might want to take advantage of the custom template repository feature.

A custom template repository is an AL-Go for GitHub repository (without any apps), which is used as a template for the remaining AL-Go for GitHub repositories. As an example, if you are using a custom delivery script, which you want to have in all your repositories, you can create an empty AL-Go for GitHub repository, place the delivery script in the .github folder and use that repository as a template when running Update AL-Go system files in your other repositories.

This would make sure that all repositories would have this script (and updated versions of the script) in the future.

The items, which are currently supported from custom template repositories are:

- Repository script overrides in the .github folder
- Project script overrides in the .AL-Go folder
- Custom workflows in the .github/workflows folder
- Custom jobs in any AL-Go for GitHub workflow
- Changes to repository settings in .github/AL-Go-settings.json
- Changes to project settings in .AL-Go/settings.json

**Note** that an AL-Go for GitHub custom template repository can be private or public.

## Your own version of AL-Go for GitHub

For experts only, following the description [here](Contribute.md) you can setup a local fork of **AL-Go for GitHub** and use that as your templates. You can fetch upstream changes from Microsoft regularly to incorporate these changes into your version and this way have your modified version of AL-Go for GitHub.

> [!NOTE]
> Our goal is to never break repositories, which are using standard AL-Go for GitHub as their template. We almost certainly will break you at some point in time if you create local modifications to scripts and pipelines.

______________________________________________________________________

[back](../README.md)
