# Continuous Deployment

Continuous Deployment is currently only supporting sandox environments (like **QA** or **FAT** environments)

Much like with continuous delivery, you need to setup an authentication context and then you need to setup an environment.

The authentication context can use **impersonation** (which uses a **refreshtoken** that is valid for **90** days) or **S2S** (which uses **ClientId** and **ClientSecret**, which needs to be **registered** inside your **Business Central Environment**.

First thing we need to do is to create an **environment** in your **GitHub repository**, which the same name as your Business Central environment.

Navigate to your single-project repository (**repo1**), select **Settings** and **Environments** and click **New environment**. Enter the name of your Business Central environment and click **Configure environment**

| ![image](https://user-images.githubusercontent.com/10775043/232294280-cc92b21b-f5ae-4381-b63b-e05b72159486.png) |
|-|

In the environment configuration screen, Click **Add secret** under **environment secrets**. Create a secret called AUTHCONTEXT and use one of the two mechanisms described below to create the auth context value:

## Using Impersonation
Easiest way to create an authentication context with impersonation for AL-Go for GitHub is to use the following PowerShell line from a machine with the BcContainerHelper module installed:

```
New-BcAuthContext -includeDeviceLogin | New-ALGoAuthContext | set-Clipboard
```

This command will display the well-known device login text: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code XXXXXXX to authenticate.

Complete the login with a Business Central user, which has access to deploy applications in the environment setup for continuous deployment. This will generate an Aothorization context for the environment and Copy it automatically to your clipboard.

Return to the "Add Secret" dialog from the environment configuration screen, paste the secret into the "Value" field, and click **Add secret**.

| ![image](https://user-images.githubusercontent.com/10775043/232296180-7ef20c2c-6a2a-4127-b524-7646512994e2.png) |
|-|

Now, select **Actions** and select the **CI/CD** workflow and click **Run workflow**. Inspect the workflow and see that deployment now also deploys your apps:

| ![image](https://user-images.githubusercontent.com/10775043/232300284-49ca8a4c-bd91-46b8-9608-76f4a6289f0f.png) |
|-|

Note that you need to update the AuthContext secret every 90 days for now.

## Using S2S
For using **S2S**, you need to do some preparation first. Follow [this](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/automation-apis-using-s2s-authentication) description to setup an **AAD App** and register it inside the **Business Central environment** you want to deploy to.

Once this is done, you can then create an Authentication context secret by using this PowerShell line from a machine with the BcContainerHelper module installed:

```
New-BcAuthContext -clientID $clientID -clientSecret $clientSecret -tenantID $tenantID | New-ALGoAuthContext | Set-Clipboard
```

Paste the value from the clipboard into the "Value" field of the **AuthContext** secret for the environment and you should be good to go.

**Note** The Environments tab in repository **Settings** is only supported in **paid SKUs** of GitHub or for **public repositories**. It is possible to use repository or organizational secrets for authenticating to environments defined in **Settings**, as an alternative to using environment secrets as we have done here, but this is not part of this workshop.

Now you might think, if this only supports sandbox environments, how do you then publish to production?

---
[Index](Index.md)&nbsp;&nbsp;[next](PublishToProduction.md)
