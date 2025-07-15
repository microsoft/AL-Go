# Continuous Delivery

Continuous Delivery is where AL-Go delivers your apps to whereever you like.

Currently, the following targets are supported:

- GitHub Packages
- Storage
- AppSource
- NuGet (work in progress)
- Custom

This workshop has already described how to setup continuous delivery for GitHub Packages [here](Dependencies2.md).

## Storage

Setting up continuous delivery to a storage account is done in the same mechanism as we did with GitHub Packages.

In order to setup **continuous delivery** to a **storage account**, you need to have an Azure Account and setup a storage account in the **Azure Portal**. You can create a **blob container** with the name of the the calculated container (based on containerName in the StorageContext) or you can add a setting called **DeliverToStorage** in your repository settings gile (.github/AL-Go-Settings.json) with a property called **CreateContainerIfNotExist** set to true for auto generation of the blob container.

```json
  "DeliverToStorage": {
    "CreateContainerIfNotExist": true
  }
```

Now, create an organizational secret called **StorageContext**. The format of the secret needs to be **compressed JSON**, containing 4 values: **storageAccountName**, **containerName**, **blobName** and either **storageAccountKey** or **sasToken**. Example:

```json
{"StorageAccountName":"accountnanme","StorageAccountKey":"HOaRhoNXXX==","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}
```

or

```json
{"storageAccountName":"accountnanme","sasToken":"?sv=2021-10-04\u0026ss=b\u0026srt=sco...","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}
```

ContainerName and BlobName can contain placeholders, like {project}, {version} and {type} which will be replaced by the real values when delivering.

> [!NOTE]
> You can use the **BcContainerHelper** function **New-ALGoStorageContext** to assist in the correct format of the secret.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/7287e068-b2d5-4fc2-b428-d0ddd4ffa0e3) |
|-|

Now create an organizational secret called **StorageContext** with the secret value.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/3e5b4ddc-bff2-4cf5-9b2a-1a3696189eaf) |
|-|

and add the deliverToStorage setting to the ALGOORGSETTINGS organizational variable:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/6b7b4072-67d0-40b2-87ae-bfa2d130162b) |
|-|

When re-running **CI/CD** afterwards, you will see that continuous delivery is now setup for a storage account as well

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/def2c115-e8c2-46dd-a7f8-4f745a93c2fb) |
|-|

Checking the storage account using Storage Explorer reveals the new container and the new app.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/5b8317ca-64c2-4c10-9cf2-53bf61c4af07) |
|-|

## AppSource

Continuous delivery to **AppSource** is supported by the AppSource template and will be included in the workshop later, but basically, creating a secret called **AppSourceContext** and setting a **AppSourceContinuousDelivery** to true in the repository settings file.

## NuGet

AL-Go for GitHub supports experimental delivery to NuGet feeds and GitHub Packages. This enables you to automatically publish your apps to package repositories for distribution and dependency management.

> [!NOTE]
> **Experimental Feature**: NuGet and GitHub Packages delivery is currently experimental but stable. The functionality has been used in production by several partners for over 6 months.

For comprehensive documentation on setting up NuGet and GitHub Packages delivery, including detailed configuration examples and troubleshooting, see the [DeliveryTargets and NuGet/GitHub Packages](../Scenarios/DeliveryTargets.md) guide.

### Quick Setup for GitHub Packages

1. **Create Personal Access Token**: Create a classic personal access token with `write:packages` scope
1. **Create Organizational Secret**: Create `GitHubPackagesContext` secret with format:
   ```json
   {"token":"ghp_YOUR_TOKEN","serverUrl":"https://nuget.pkg.github.com/YOUR_ORG/index.json"}
   ```
1. **Run CI/CD**: Your apps will automatically be published to GitHub Packages after successful builds

### Quick Setup for Custom NuGet Feed

1. **Create NuGetContext Secret**: Create `NuGetContext` secret with your custom feed URL and token
1. **Configure Dependency Resolution**: Add your feed to `trustedNuGetFeeds` setting if you want to use it for dependencies
1. **Run CI/CD**: Your apps will be delivered to the specified NuGet feed

For detailed step-by-step instructions, configuration examples, and troubleshooting, refer to the [comprehensive DeliveryTargets guide](../Scenarios/DeliveryTargets.md).

## Custom delivery

Custom delivery will be handled in an advanced part of this workshop later.

OK, so **CD** stands for **Continuous Delivery**, I thought it was **Continuous Deployment**? Well, it is actually both, so let's talk about **Continuous Deployment**...

______________________________________________________________________

[Index](Index.md)  [next](ContinuousDeployment.md)
