# Get Started

With our prerequisites in place, it is time to get started and create our first repository.

In a browser, navigate to https://aka.ms/algopte:

| ![image](https://github.com/user-attachments/assets/7ea41bbf-fbd1-4699-8521-49cf9ef4d771) |
|-|

And you should see:

| ![image](https://github.com/user-attachments/assets/6251023a-5cdf-4dc0-969d-2fd79dd5475c) |
|-|

Click **Use This Template** and select **Create a new repository**. Select your **organizational account** as **owner** and enter **repo1** as repository name. Make the repo **public** and click **Create repository**.

| ![image](https://github.com/user-attachments/assets/66e989c8-6584-43c5-a9ed-74da035c4b60) |
|-|

After a few seconds, your new repository should be ready for you.

| ![image](https://github.com/user-attachments/assets/c42701bc-517b-4da8-8bdf-1fc153dd9e73) |
|-|

In your new repository, click **Settings** -> **Actions** and verify that your repository has the permissions to run actions and reusable workflows, either all workflows or github and microsoft created actions are required.

| ![image](https://github.com/user-attachments/assets/b5da1c65-cf10-49ce-9f54-041620083996) |
|-|

Further down on the **Settings** -> **Actions** page, you also need to ensure that GitHub Actions are allowed to create pull requests.

| ![image](https://github.com/user-attachments/assets/48a210e4-3354-4c46-b91c-ef94654f44e2) |
|-|

> [!NOTE]
> Actions permissions might be controlled on the organizational level as well and might not be altered in the repository.

Now, click **Actions** in the top menu, and you should see that a CI/CD workflow has already been kicked off on our empty repository.

| ![image](https://github.com/user-attachments/assets/85b0f2b4-3f13-45e7-b7ee-ca102c6eb198) |
|-|

If the CI/CD workflow hasn't completed, wait for it to complete and click the completed workflow to see details.

| ![image](https://github.com/user-attachments/assets/58a067bd-2e13-4119-ad01-ccab24ab2595) |
|-|

Note the warnings explaining that no apps have been added. The CI/CD workflow doesn't have anything to compile yet as you didn't add any source code.

Ignore the warning about available updates for now.

After this step, we are done setting up a basic AL-Go for GitHub repository and we only need to add our apps.

So, let's add an app...

______________________________________________________________________

[Index](Index.md)  [next](AddAnApp.md)
