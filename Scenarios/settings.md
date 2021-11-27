
# Settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| type | | PTE |
| country | | us |
| artifact | | |
| companyName | | |
| repoVersion | |1.0|
| repoName | | |
| versioningStrategy |  | 0 |
| runNumberOffset |  | 0 |
| appBuild |  | 0 |
| appRevision |  | 0 |
| keyVaultName | | |
| licenseFileUrlSecretName | | LicenseFileUrl |
| insiderSasTokenSecretName | | InsiderSasToken |
| ghTokenWorkflowSecretName | | GhTokenWorkflow |
| adminCenterApiCredentialsSecretName | | AdminCenterApiCredentials |
| supportedCountries | | [ ] |
| appFolders | | [ ] |
| testFolders | | [ ] |
| applicationDependency | | 19.0.0.0 |
| appSourceCopMandatoryAffixes | | [ ] |
| templateUrl | | |
| appDependencyProbingPaths | | [ ] |

# Advanced settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| appDependencies | | [ ] |
| testDependencies | | [ ] |
| installApps | | [ ] |
| installTestApps | | [ ] |
| enableCodeCop | | false |
| enableUICop | | false |
| keyVaultCertificateUrlSecretName | | |
| keyVaultCertificatePasswordSecretName | | |
| keyVaultClientIdSecretName | | |
| codeSignCertificateUrlSecretName | | CodeSignCertificateUrl |
| codeSignCertificatePasswordSecretName | | CodeSignCertificatePassword |
| githubRunner | Specifies which github runner will be used for the pipeline, which is the most time consuming task. Currently, you cannot change which runner is used for all the house-keeping tasks. These will always be run on the github hosted runner: windows-latest | windows-latest |
| alwaysBuildAllProjects | This setting only makes sense if the repository is setup for multiple projects.<br />Standard behavior of the CI/CD workflow is to only build the projects, in which files have changes when running the workflow due to a push or a pull request | false |

# Expert settings (rarely used)
| Name | Description | Default value |
| :-- | :-- | :-- |
| installTestRunner | Determines wheather the test runner will be installed in the pipeline. If there are testFolders in the project, this setting will be true. | |
| installTestFramework | Determines whether the test framework apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test framework apps, this setting will be true | |
| installTestLibraries | Determines whether the test libraries apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test library apps, this setting will be true | |
| installPerformanceToolkit | Determines whether the performance test toolkit apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the performance test toolkit apps, this setting will be true | |
| enableAppSourceCop | Determines whether the AppSourceCop will be enabled in the pipeline. If the project type is AppSource App, then the AppSourceCop will be enabled by default. You can set this value to false to force the AppSourceCop to be disabled | |
| enablePerTenantExtensionCop | Determines whether the PerTenantExtensionCop will be enabled in the pipeline. If the project type is PTE, then the PerTenantExtensionCop will be enabled by default. You can set this value to false to force the PerTenantExtensionCop to be disabled | |
| doNotBuildTests | This setting forces the pipeline to NOT build and run the tests in testFolders | false |
| doNotRunTests | This setting forces the pipeline to NOT run the tests in testFolders. Tests are still being built and published | false |
| memoryLimit | Specifies the memory limit for the build container. By default, this is left to BcContainerHelper to handle and will currently be set to 8G | |
