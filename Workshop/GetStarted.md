# Get Started

With our prerequisites in place, it is time to get started and create our first repository.

In a browser, navigate to https://aka.ms/algopte:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/1c6a3d1d-b712-4837-9654-58fccbdd911e) |
|-|

And you should see:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/7e74715a-0e9a-4f7a-b261-a7107fad8888) |
|-|

Click **Use This Template** and select **Create a new repository**. Select your **organizational account** as **owner** and enter **repo1** as repository name. Make the repo **public** and click **Create repository**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/32ce5b05-b347-4174-b83d-e344756f2d06) |
|-|

After a few seconds, your new repository should be ready for you.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/11d7f51d-f38c-4163-a929-a55f2360911d) |
|-|

Navigate to the repository, go to the Settings tab and select Actions from the sidebar.

<img width="615" alt="image" src="https://github.com/user-attachments/assets/c31b601c-73e7-4908-98de-32b6529145fc" />

Scroll to the Workflow permissions section and ensure "Read and write permissions" is selected. This allows workflows to create or modify pull requests.
If necessary, enable the option "Allow GitHub Actions to create and approve pull requests".

<img width="639" alt="image" src="https://github.com/user-attachments/assets/954430bb-3c84-4235-89b2-ee0128631c44" />

Click **Actions**, and you should see that a CI/CD workflow has already been kicked off on our empty repository.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/e13fc12d-c36d-4014-bbe5-0f8003c90bb0) |
|-|

Wait for the CI/CD workflow to complete and click the completed workflow to see details.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/cc181fb1-0496-45aa-87c5-69fd000d772f) |
|-|

Note the warnings explaining that no apps have been added. The CI/CD workflow doesn't have anything to compile yet as you didn't add any source code.

Ignore the warning about available updates for now.

After this step, we are done setting up a basic AL-Go for GitHub repository and we only need to add our apps.

So, let's add an app...

______________________________________________________________________

[Index](Index.md)  [next](AddAnApp.md)
