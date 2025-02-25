# Publish To AppSource

*Prerequisites: An app in AppSource and a GitHub Repository based on the [AL-Go-AppSource](https://aka.ms/AL-Go-AppSource) template with the source code for that app.*

> [!NOTE]
> The initial creation and upload of the your app on AppSource cannot be automated in AL-Go for GitHub. You have to do the first upload of marketing material manually and also the first upload of your app. After this, AL-Go for GitHub can be setup to publish updates to your app either continuously or manually by running a Workflow.

As a sample app, I will use my AppSource app called [BingMaps.AppSource](https://appsource.microsoft.com/da-dk/product/dynamics-365-business-central/PUBID.microsoftdynsmb%7CAID.bingmapsintegration%7CPAPPID.4270bff7-c860-434f-b09a-0f3e37d243fd?tab=Overview), located on [microsoft/bcsamples-bingmaps.appsource](https://github.com/microsoft/bcsamples-bingmaps.appsource).

## Authentication to AppSource

In order to get started, you need a way to authenticate to the Partner Center ingestion API. This can be done using Service 2 Service authentication (which is recommended for workflows and pipelines) or you can use User Impersonation.

### Service 2 Service (S2S)

To get started with S2S, you need to complete Step 1 from [here](https://docs.microsoft.com/en-us/azure/marketplace/azure-app-apis). After this, you should have a ClientID and a of your Microsoft Entra Application and the actual authentication is done using the New-BcAuthContext function from BcContainerHelper:

```powershell
$authcontext = New-BcAuthContext `
    -clientID $PublisherAppClientId `
    -clientSecret (ConvertTo-SecureString -String $PublisherAppClientSecret -AsPlainText -Force) `
    -Scopes "https://api.partner.microsoft.com/.default" `
    -TenantID "<your AAD tenant>"
New-ALGoAppSourceContext -authContext $authContext | Set-Clipboard
```

### User Impersonation

If you, for some reason, can’t or won’t create an Microsoft Entra Application for S2S authentication, then the other option for getting an authcontext is to use user impersonation. For this, you can also use the New-BcAuthContext function from BcContainerHelper:

```powershell
$authcontext = New-BcAuthContext `
    -includeDeviceLogin `
    -Scopes "https://api.partner.microsoft.com/user_impersonation offline_access" `
    -tenantID "<your AAD tenant>"
New-ALGoAppSourceContext -authContext $authContext | Set-Clipboard
```

This will invoke the device flow and display a code, which you need to use when authenticating to https://aka.ms/devicelogin

## Add AppSourceContext secret to AL-Go for GitHub

After running one of the code snippets above, you should now have the AuthContext in the Clipboard and you can create a secret by navigating to Settings -> Secrets and variables -> Actions, click **New repository secret**. Create a secret called AppSourceContext and paste the value into the secret.

![New Secret](https://github.com/microsoft/AL-Go/assets/10775043/faac0de8-032a-4336-a8b0-e176d92e23f7)

## Configuration

Beside the AppSourceContext secret, you will need to add a `DeliverToAppSource` structure to your project settings file.

If your repository contains multiple projects, every project can contain an AppSource offering. One AL-Go project can only hold one AppSource offering (one AppSource Product Id) + a number of library apps. If your library apps are only used by this AppSource offering, then it is totally fine to place them in the same project as the main app. If these library apps are used by multiple AppSource offerings (multiple main apps), the should be placed in seperate projects or repositories.

In your project configuration, you will need the AppSource Product Id (not your app id). You can find your AppSource Product Id in the address bar of the browser in partner center when looking at your AppSource offering

![AppSource App](https://github.com/microsoft/AL-Go/assets/10775043/71b9f10e-2046-46cc-9cd5-13a0d1efd486)

The **productId GUID is mandatory** and must be specified in `deliverToAppSource` like this:

```json
  "deliverToAppSource": {
    "productId": "5fbe0803-a545-4504-b41a-d9d158112360",
    "continuousDelivery": false,
    "mainAppFolder": "BingMaps-AppSource",
    "includeDependencies": [
      "Freddy Kristiansen_*.app"
    ]
  },
  "generateDependencyArtifact": true
```

The other properties in the deliverToAppSource structure are **optional** and determines whether or not Continuous Delivery (CD) is enabled during CI/CD, what appFolder contains the main app and which dependencies to include dependencies from other projects/repositories.

> [!NOTE]
> The includeDependencies requires you to also set `generateDependencyArtifact` to `true` (like shown above). GenerateDependencyArtifact will create a build and a release artifact with the dependent apps used for building the app. includeDependencies will include a number of these apps as library apps when submitting.

> [!NOTE]
> When having multiple projects in an AL-Go for GitHub repository, you should set `UseProjectDependencies` to `true` in the **repository settings file** *(.github/AL-Go-Settings.json)* and run Update AL-Go System Files to only build the library apps once and reuse them in the depending projects.

The BingMaps.AppSource repository has 2 projects: **Main App** and **Library Apps**. The Main App projects contains three apps: **BingMaps-AppSource**, **BingMaps-AppSource.Test**, **BingMaps.Common**. The Library Apps contains only one app: **FreddyDK.Licensing**. The Main AppFolder is BingMaps-AppSource and all dependencies with Freddy Kristiansen as the publisher from other projects will be included as library apps. The BingMaps.Common app is always included (if referenced by the main app). Navigate to [microsoft/bcsamples-bingmaps.appsource](https://github.com/microsoft/bcsamples-bingmaps.appsource) and investigate.

## Delivering

If you navigate to the BingMaps.AppSource repository, you should be able to see the delivery steps and see that AL-Go publishes the main App + the library Apps to AppSource

![Delivery](https://github.com/microsoft/AL-Go/assets/10775043/c002d29c-96a6-4ef5-b281-ad2518117ca8)

## Preview

If you have set ContinuousDelivery to true, every app will be delivered to AppSource and taken through validation and made available in AppSource as preview. You then need to press **Go Live** in partner center or run the Publish To AppSource workflow in AL-Go for GitHub in order to publish the app to production.

______________________________________________________________________

[back](../README.md)
