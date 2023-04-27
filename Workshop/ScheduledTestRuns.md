# Scheduled Test Runs
Building and testing your apps with the latest and the upcoming versions of Business Central is a crucial part of your DevOps setup. You will know when your app will be broken and can be prepared for the next version way ahead of time, making sure that your customers are not held up by your apps.

To be able to run the workflows for testing against **Next Minor** and **Next Major** versions of Business Central, you will need an **insider SAS Token**, which is available on https://aka.ms/collaborate (Select **Packages** and **Working with Business Central insider builds**). The Direct URL is [here](https://partner.microsoft.com/en-us/dashboard/collaborate/packages/9387), but you will have to have an account with collaborate in order to use the link.

Create an organizatonal secret called **INSIDERSASTOKEN**, containing the insider SAS Token from collaborate.

| ![image](https://user-images.githubusercontent.com/10775043/232338769-abe5c76d-6ac5-4b1a-8fb8-a972333f0e44.png) |
|-|

Use **https://crontab.guru** to create a crontab for the schedule you want to run your workflows on. I have selected the following:
- I want to run the **Test Current** workflow every day at 2 in the morning. The crontab for that is: 0 2 * * *
- I want to run the **Test Next Minor** workflow every Saturday at 2 in the morning. The crontab for that is: 0 2 * * 6
- I want to run the **Test Next Major** workflow every Sunday at 2 in the morning. The crontab for that is: 0 2 * * 0

In your single-project repository, select **Code**, navigate to **.github/AL-Go-Settings.json**, remove the 2 settings (**useCompilerFolder** and **doNotPublishApps**) we added to run tests and add 3 new settings:

| ![image](https://user-images.githubusercontent.com/10775043/232339274-3c295485-ccc3-48b1-ab57-cd9ad85c5e04.png) |
|-|

Now, select **Actions** and run the **Update AL-Go System Files** workflow in order for the schedule to take effect. You can see the changes to the workflows done by the **Update AL-Go System Files** workflow in the **pull request**.

| ![image](https://user-images.githubusercontent.com/10775043/232339690-047441f5-cd65-43f9-a40a-5b46e923c77d.png) |
|-|

Now, modify .github/Test Current.settings.json and add the two settings (useCompilerFolder and doNotPublishApps) in that one

| ![image](https://user-images.githubusercontent.com/10775043/232340747-6eb81ab9-0bb2-4947-9416-8af2108de834.png) |
|-|

Which now means that your Test Current workflow, which runs every night will run all tests and other workflows will not.

Now we know when our app gets broken and doesn't work anymore, but what about performance regressions?

---
[Index](Index.md)&nbsp;&nbsp;[next](PerformanceTesting.md)
