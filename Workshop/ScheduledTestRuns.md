# Scheduled Test Runs

Building and testing your apps with the latest and the upcoming versions of Business Central is a crucial part of your DevOps setup. You will know when your app will be broken and can be prepared for the next version way ahead of time, making sure that your customers are not held up by your apps.

AL-Go for GitHub includes 3 workflows for this purpose: **Test Current**, **Test Next Minor** and **Test Next Major**, which will build and test your app against the corresponding versions of Business Central.

These workflows can be run manually by simply selecting the workflow and clicking **Run workflow**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/7747d778-40f8-4d3e-9e26-02e3cf410834) |
|-|

Microsoft recommands running these workflows on a schedule to ensure that your app is ready for upcoming releases at all times and at the same time keeping compatibility with the versions you want to support.

Use **Bing Copilot Chat** and ask it to generate the crontab you want (ex. *Create a crontab which triggers every saturday at 2am*) or use **https://crontab.guru** to create a crontab for the schedule you want to run your workflows on. I have selected the following for some of my apps:

- I want to run the **Test Current** workflow every day at 2 in the morning. The crontab for that is: 0 2 * * \*
- I want to run the **Test Next Minor** workflow every Saturday at 2 in the morning. The crontab for that is: 0 2 * * 6
- I want to run the **Test Next Major** workflow every Sunday at 2 in the morning. The crontab for that is: 0 2 * * 0

In your single-project repository, select **Code**, navigate to **.github/AL-Go-Settings.json**, remove the 2 settings (**useCompilerFolder** and **doNotPublishApps** ) we added to run tests and add 3 new settings:

```json
  "CurrentSchedule": "0 2 * * *",
  "NextMinorSchedule": "0 2 * * 6",
  "NextMajorSchedule": "0 2 * * 0"
```

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/c82e1393-e7b1-4e3a-8b64-488c107fff7b) |
|-|

Now, select **Actions** and run the **Update AL-Go System Files** workflow in order for the schedule to take effect. You can see the changes to the workflows done by the **Update AL-Go System Files** workflow in the **pull request**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/4a65a694-12b5-4896-8323-1b49d26c1a56) |
|-|

Merge the Pull Request and remove the temporary branch.

Now, you could modify **.github/Test Current.settings.json** and add the two settings (useCompilerFolder and doNotPublishApps) in that one

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/e17aaebc-4cb9-405e-89d7-9aee55eba66f) |
|-|

Which now means that your Test Current workflow, which runs every night will run all tests and other workflows will not.

> \[!NOTE\]
> While the name of the workflow specific settings file is based on the workflow title (**Test Next Major.settings.json**), the workflow schedule setting needs to be in AL-Go-Settings.json and is based on the filename of the workflow (**NextMajorSchedule**):
>
> ![image](https://github.com/microsoft/AL-Go/assets/10775043/6d8f15f3-8415-43d1-b7b6-3e08c545e500)

Now we know when our app gets broken and doesn't work anymore, but what about performance regressions?

______________________________________________________________________

[Index](Index.md)  [next](PerformanceTesting.md)
