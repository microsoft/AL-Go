# Run tests

Run normal tests from `testFolders` against an existing Business Central container.

The action reads analyzed settings from `Settings` and reconnects to the kept-alive build container using `containerName` and `containerCredential`; `project` selects the project folder, and `installTestAppsJson` supplies installed test-app paths from earlier jobs.

Compiled apps are matched to normal `testFolders`; eligible installed test apps are added from `installTestAppsJson`, and matching disabled-test files are applied. The built-in runner uses AlTool and BcContainerHelper metadata to execute each selected app and append JUnit results to `TestResults.xml`.

Produced results remain in the project folder for AnalyzeTests and are copied to `.buildartifacts/TestResults.xml`. The action refreshes `ContainerEventLog.evtx` after execution.

The override `.AL-Go/RunTestsInBcContainer.ps1` replaces the built-in test runner. It is invoked once per selected test app with `-parameters` containing the standard BcContainerHelper test arguments and returns whether all tests passed.
