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

Now select **Actions** and locate the **Create a new test app** action and click **Run workflow**.

| ![image](https://user-images.githubusercontent.com/10775043/232327235-bd4350f7-d05f-423b-a69b-0b0c226180b3.png) |
|-|







Running tests every time you change your code is nice, but what about running your tests with latest or future versions of Business Central?

---
[Index](Index.md)&nbsp;&nbsp;[next](ScheduledTestRuns.md)
