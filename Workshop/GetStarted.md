# Get Started
With our prerequisites in place, it is time to get started and create our first repository.

In a browser, navigate to https://aka.ms/algopte:

| ![image](https://user-images.githubusercontent.com/10775043/231536061-8594cfec-d312-4f5b-9ff4-a3d0cf46ab69.png) |
|-|

Click **Use This Template** and select **Create a new repository**. Select your **organizational account** as **owner** and enter **repo1** as repository name. Make the repo **public** and click **Create repository form template**.

| ![image](https://user-images.githubusercontent.com/10775043/231535787-43d8af7d-1554-4e11-9753-8e7d7d21401c.png) |
|-|

After this step, we are done setting up a basic AL-Go for GitHub repository and we only need to add our apps.

For the purpose of this workshop, we will be using the preview version of AL-Go for GitHub. Under **Actions**, select the **Update AL-Go System Files** workflow and click **Run workflow**. Enter **microsoft/AL-Go-PTE@preview** in the **Template Repository URL** field and say **Y** to **Direct COMMIT**.

| ![image](https://user-images.githubusercontent.com/10775043/231537086-4eb4ae5c-6dcb-4e2d-be1b-26df4a67f227.png) |
|-|

The Update AL-Go System Files workflow will start and after a few minutes, your repository have been upgraded to the preview version of AL-Go for GitHub.
If you click **Actions**, you will also see that a **CI/CD workflow** was kicked off as a result of upgrading your repository:

| ![image](https://user-images.githubusercontent.com/10775043/231539948-48441647-6215-4f5e-abf2-dea1317a8e89.png) |
|-|

Obviously, the CI/CD workflow didn't compile anything as you didn't add any source code. By clicking the workflow in the list, and scrolling down, you should see:

| ![image](https://user-images.githubusercontent.com/10775043/231540402-05af1336-0f60-45e7-a86c-501a95a657de.png) |
|-|

Note the three warnings explaining that no apps have been added.

So, let's add an app...

---
[Index](Index.md)&nbsp;&nbsp;[next](AddAnApp.md)
