# Automated Tests
In order to run automated tests, you need to change a few things in settings.

During prerequisites we added two AL-Go settings:

```
  "useCompilerFolder": true
  "doNotPublishApps": true
```

These settings means that AL-Go will use a CompilerFolder to compile the apps instead of a container and that we will never actually publish the apps (meaning that Test runs are also disabled).

In this step, we will add a test app to the single-project repository and see how AL-Go handles test runs and test results.

So, navigate to your single-project repository, locate the .github/AL-Go-Settings.json file and add the following two settings:

```
  "useCompilerFolder": false
  "doNotPublishApps": false
```

| ![image](https://user-images.githubusercontent.com/10775043/232327081-6c6f7be3-fa18-41d2-98b3-ff540a953125.png) |
|-|

Now select **Actions** and locate the **Create a new test app** action and click **Run workflow** and use the following parameters:

| Name | Value |
| :-- | :-- |
| Project name | `.` |
| Name | `app1.test` |
| Publisher | `<your publisher name>` |
| ID Range (from..to) | `70000..99999` |
| Include Sample Code | `Y` |
| Direct COMMIT | `N` |

| ![image](https://user-images.githubusercontent.com/10775043/232327235-bd4350f7-d05f-423b-a69b-0b0c226180b3.png) |
|-|

Inspect and **merge** the pull request. Now completion of the merge pull request **will be much slower than before**, as the GitHub hosted runners needs to download the Business Central Generic image and the artifacts every single time. When the workflow is done, you should see that below the artifacts produced by the **CI/CD** workflow, there is a summary field with the test results.

| ![image](https://user-images.githubusercontent.com/10775043/232337935-f20f3e8b-94a7-42cf-a97a-37ce09f9a479.png) |
|-|

As already mentioned, running complete builds with full tests does take more time than containerless compiling. We are working on improving this.

Our recommendation is that you run your full test suite during **CI/CD**, but it is possible with **AL-Go for GitHub**, to not run the tests during **CI/CD** and then postpone them to a nightly test run using a scheduled run of the **Test Current** workflow.

So, let's see what it takes to setup scheduled runs for running the tests with **latest** or **future versions** of Business Central?

---
[Index](Index.md)&nbsp;&nbsp;[next](ScheduledTestRuns.md)
