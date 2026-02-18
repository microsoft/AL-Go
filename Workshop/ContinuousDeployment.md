# Continuous Deployment

Using Continuous Deployment you can deploy your apps to an online environment continuously. Much like with continuous delivery, you need to setup an authentication context and then you need to setup an environment.

> [!NOTE]
> The authentication context can use **impersonation** (which uses a **refreshtoken**, which typically is valid for **90** days) or **S2S** (which uses **ClientId** and **ClientSecret**, which needs to be **registered** inside your **Business Central Environment**.

First thing we need to do is to create an **environment** in your **GitHub repository** with a name, which identifies your Business Central environment.

Navigate to your single-project repository (**repo1**), select **Settings** -> **Environments** and click **New environment**. Enter a name for your Business Central environment and click **Configure environment**

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/72dc1a40-bb14-4e2a-9d8a-35f36bf623a3) |
|-|

In the environment configuration screen, Click **Add secret** under **Environment secrets**. Create a secret called AUTHCONTEXT and use one of the two mechanisms described below to create the auth context value:

> [!NOTE]
> The Environments tab in repository **Settings** is only supported in **paid SKUs** of GitHub or for **public repositories**. It is possible to use repository or organizational secrets for authenticating to environments defined in **Settings**, as an alternative to using environment secrets as we have done here, but this is not part of this workshop.

After creating the environment and the AUTHCONTEXT secret, you should create a setting structure called DeployTo followed by your GitHub environment name. Read more about the DeployTo setting [here](https://aka.ms/algosettings#DeployTo)).
If your actual Business Central environment has a different name than your GitHub environment, you can add an EnvironmentName property to the DeliverTo settings like:

```json
  "DeployToMy-QA": {
    "EnvironmentName": "QA",
    "continuousDeployment": true
  }
```

At this time, these settings cannot be added as environment variables, we might add this in the future.

## Creating an AUTHCONTEXT that uses impersonation

Easiest way to create an authentication context with impersonation for AL-Go for GitHub is to use the following PowerShell line from a machine with the latest **BcContainerHelper** module installed:

```powershell
New-BcAuthContext -includeDeviceLogin | New-ALGoAuthContext | set-Clipboard
```

This command will display the well-known device login text: **To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code XXXXXXX to authenticate.**

Complete the login with a Business Central user, which has access to deploy applications in the environment setup for continuous deployment. This will generate an Authorization context for the environment and Copy it automatically to your clipboard.

Return to the "Add Secret" dialog from the environment configuration screen, paste the secret into the "Value" field, and click **Add secret**.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/7d825d02-a22f-41fc-b291-08dea0685676) |
|-|

Now, select **Actions** and select the **CI/CD** workflow and click **Run workflow**. Inspect the workflow and see that deployment now also deploys your apps:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/2e390351-f9a5-49a5-a50c-25671022633c) |
|-|

The URL under the deployment will navigate to the environment.

Opening the Business Central environment and navigating to **Extension Management** reveals that both apps from repo1 has been installed in the development scope. If the environment was a production environment, the apps would have been installed in the Global Scope as Per Tenant Extensions.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/40e5f9de-319c-4151-aa31-98a32732bfce) |
|-|

> [!NOTE]
> You need to update the AuthContext secret every 90 days for now.

## Creating an AUTHCONTEXT that uses S2S

For using **S2S**, you need to do some preparation first. Follow [this](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/automation-apis-using-s2s-authentication) description to setup a **Microsoft Entra application** and register it inside the **Business Central environment** you want to deploy to.

> [!TIP]
> The term "application" in the context of Microsoft Entra can cause some confusion. You create an application registration, and allow access to X resources through that application registration.
>
> The application registration is allowed to forward the access token obtained with these permissions to a set of URLs. Now the owner of the ClientID and the ClientSecret or certificate can now authenticate and obtain the permissions assigned to that app registration.
>
> The Microsoft Entra application registration is not tied to a specific Business Central app, customer, partner, vendor, person or purpose - it is up to the creator of the app registration to determine this. You can have one application registration, which you can use for various test purposes (many different apps), while having more purposefull application registrations for production.
>
> Secrets and certificates can be revoked (if compromised) and permissions can be changed - this indirect way of authentication does provide more security than a simple username/password, which everybody understands.

Once this is done, you can then create an Authentication context secret by using this PowerShell line from a machine with the latest BcContainerHelper module installed:

```powershell
New-BcAuthContext -clientID $clientID -clientSecret $clientSecret -tenantID $tenantID | New-ALGoAuthContext | Set-Clipboard
```

Paste the value from the clipboard into the "Value" field of the **AuthContext** secret for the environment and you should be good to go.

## Custom Deployments

AL-Go can also be setup for custom deployment when you want to deploy to non-SaaS environments. More about this in the advanced section.

## Important Note: Automatic Skip Behavior

Deployment jobs automatically skip execution when no app artifacts are available.

This skip behavior prevents deployment errors and ensures that environments are only targeted when there are actual artifacts to deploy. You'll see the deployment step appear as skipped in the workflow summary when this occurs.

This section was about Continuous Deployment, but you might not want to deploy to production environments continuously - how can we publish to production on demand?

______________________________________________________________________

[Index](Index.md)  [next](PublishToProduction.md)
