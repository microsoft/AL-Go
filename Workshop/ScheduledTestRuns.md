# Scheduled Test Runs

Building and testing your apps with the latest and the upcoming versions of Business Central is a crucial part of your DevOps setup. You will know when your app will be broken and can be prepared for the next version way ahead of time, making sure that your customers are not held up by your apps.

AL-Go for GitHub includes 3 workflows for this purpose: **Test Current**, **Test Next Minor** and **Test Next Major**, which will build and test your app against the corresponding versions of Business Central.

These workflows can be run manually by simply selecting the workflow and clicking **Run workflow**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5cec9a1b-04d0-4010-a647-bb631903e80e) |
|-|

Microsoft recommands running these workflows on a schedule to ensure that your app is ready for upcoming releases at all times and at the same time keeping compatibility with the versions you want to support.

Use **Bing Copilot Chat** and ask it to generate the crontab you want (ex. *Create a crontab which triggers every saturday at 2am*) or use **https://crontab.guru** to create a crontab for the schedule you want to run your workflows on. I have selected the following for some of my apps:
- I want to run the **Test Current** workflow every day at 2 in the morning. The crontab for that is: 0 2 * * *
- I want to run the **Test Next Minor** workflow every Saturday at 2 in the morning. The crontab for that is: 0 2 * * 6
- I want to run the **Test Next Major** workflow every Sunday at 2 in the morning. The crontab for that is: 0 2 * * 0

In your single-project repository, select **Code**, navigate to **.github/AL-Go-Settings.json**, remove the 2 settings (**useCompilerFolder** and **doNotPublishApps** ) we added to run tests and add 3 new settings:

```json
  "CurrentSchedule": "0 2 * * *",
  "NextMinorSchedule": "0 2 * * 6",
  "NextMajorSchedule": "0 2 * * 0"
```

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/480c759b-c276-439e-9d89-af26ce4780dd) |
|-|

Now, select **Actions** and run the **Update AL-Go System Files** workflow in order for the schedule to take effect. You can see the changes to the workflows done by the **Update AL-Go System Files** workflow in the **pull request**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/e868a217-010d-4fea-8be8-e707e5e76900) |
|-|

Now, modify **.github/Test Current.settings.json** and add the two settings (useCompilerFolder and doNotPublishApps) in that one

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/1028a813-87db-438e-a271-ef8e87415799) |
|-|

Which now means that your Test Current workflow, which runs every night will run all tests and other workflows will not.

> [!NOTE]
> While the name of the workflow specific settings file is based on the workflow title (**Test Next Major.settings.json**), the workflow schedule setting needs to be in AL-Go-Settings.json and is based on the filename of the workflow (**NextMajorSchedule**):
> 
> ![image](https://github.com/microsoft/AL-Go/assets/10775043/b3abf297-2ee6-4160-b1c1-ddeeab985cda)

Now we know when our app gets broken and doesn't work anymore, but what about performance regressions?

---
[Index](Index.md)&nbsp;&nbsp;[next](PerformanceTesting.md)
