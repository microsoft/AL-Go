# Automated Tests
In order to run automated tests, you need to change a few things in settings.

During prerequisites we added two AL-Go settings to the ALGOORGSETTINGS organizational variable:

```json
  "useCompilerFolder": true,
  "doNotPublishApps": true
```

These settings means that AL-Go will use a CompilerFolder functionality to compile the apps instead of a container and that we will never actually publish the apps (meaning that Test runs are also disabled).

In this step, we will add a test app to the single-project repository and see how AL-Go handles test runs and test results.

So, navigate single-project repository, locate the .github/AL-Go-Settings.json file and add the following two settings:

```json
  "useCompilerFolder": false,
  "doNotPublishApps": false
```

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/f94be356-0187-4add-9c3e-f3eaf1423cd8) |
|-|

Now select **Actions** and locate the **Create a new test app** action and click **Run workflow** and use the following parameters:

| Name | Value |
| :-- | :-- |
| Project name | `.` |
| Name | `app1.test` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `70000..99999` |
| Include Sample Code | `yes` |
| Direct Commit | `no` |

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/eab3a42e-a73c-4c13-bc05-7cc2c7a4b05e) |
|-|

Inspect and **merge** the pull request. Now completion of the merge pull request **will be much slower than before**, as the GitHub hosted runners needs to download the Business Central Generic image and the artifacts every single time. When the workflow is done, you should see that below the artifacts produced by the **CI/CD** workflow, there is a summary field with the test results.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/f0f570ae-bd2b-4f41-b3e0-a9bc406d9ad3) |
|-|

As already mentioned, running complete builds with full tests does take more time than containerless compiling. We are working on improving this.

> [!NOTE]
> Our recommendation is that you run your full test suite during **CI/CD**, but it is possible with **AL-Go for GitHub**, to not run the tests during **CI/CD** and then postpone them to a nightly test run using a scheduled run of the **Test Current** workflow.

So, let's see what it takes to setup scheduled runs for running the tests with **latest** or **future versions** of Business Central?

---
[Index](Index.md)&nbsp;&nbsp;[next](ScheduledTestRuns.md)
