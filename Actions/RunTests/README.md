# Run tests

Run normal tests from `testFolders` against an existing Business Central container.

The action reads analyzed settings from `Settings` and reconnects to the kept-alive build container using `containerName` and `containerCredential`; `project` selects the project folder, and `installTestAppsJson` supplies installed test-app paths from earlier jobs.

Compiled apps are matched to normal `testFolders`, eligible installed test apps are added from `installTestAppsJson`, and matching disabled-test files are applied.

The built-in runner installs the latest prerelease of `Microsoft.Dynamics.BusinessCentral.Development.Tools` and uses `al listtests --appfile` to discover metadata and tests locally from each exact package. BcContainerHelper remains responsible for container connection settings, company discovery, and event-log export.

The built-in runner ignores a nonblank `useSeparateTestAction.testType` with a warning because `listtests` does not support TestType filtering. A custom `.AL-Go/RunTestsInBcContainer.ps1` override receives the configured value.
