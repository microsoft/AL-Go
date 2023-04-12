# Get Started
In a browser, navigate to https://aka.ms/algopte:

| ![image](https://user-images.githubusercontent.com/10775043/231396338-d4703463-89a6-4c6b-a69c-d57a4c581946.png) |
|-|

Click **Use This Template** and select **Create a new repository**. Select your **organizational account** as **owner** and enter **app1** as repository name. Make the repo **public** and click **Create repository form template**.

| ![image](https://user-images.githubusercontent.com/10775043/231396623-96e8adee-0ac3-445a-8785-f950822ed0ea.png) |
|-|

After this step, we are done setting up a basic AL-Go for GitHub repository and we only need to add our apps.

For the purpose of this workshop, we will be using the preview version of AL-Go for GitHub. Under **Actions**, select the **Update AL-Go System Files** workflow and click **Run workflow**. Enter **microsoft/AL-Go-PTE@preview** in the **Template Repository URL** field and say **Y** to **Direct COMMIT**.

| ![image](https://user-images.githubusercontent.com/10775043/231397188-414bef25-a00b-447f-ae9c-3d014afac9f0.png) |
|-|

The Update AL-Go System Files workflow will start and after a few minutes, your repository have been upgraded to the preview version of AL-Go for GitHub.
If you click **Actions**, you will also see that a **CI/CD workflow** was kicked off as a result of upgrading your repository:

| ![image](https://user-images.githubusercontent.com/10775043/231398788-6ab2acc2-f235-4f93-9772-f51be1d982a2.png) |
|-|

Obviously, the CI/CD workflow didn't compile anything as you didn't add any source code. By clicking the workflow in the list, and scrolling down, you should see:

| ![image](https://user-images.githubusercontent.com/10775043/231409580-489edea8-53c2-47a9-9f89-5babfa341c9c.png) |
|-|

Note the three warnings explaining that no apps have been added.

So, let's add an app...

---
[Index](Index.md)&nbsp;&nbsp;[next](AddAnApp.md)
