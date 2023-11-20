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

Create an organizational secret called **StorageContext**. The format of the secret needs to be **compressed JSON**, containing 4 values: **storageAccountName**, **containerName**, **blobName** and either **storageAccountKey** or **sasToken**. Example:

```json
{"StorageAccountName":"accountnanme","StorageAccountKey":"HOaRhoNXXX==","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}
```

or

```json
{"storageAccountName":"accountnanme","sasToken":""?sv=2021-10-04\u0026ss=b\u0026srt=sco...","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}
```

ContainerName and BlobName can contain placeholders, like {project}, {version} and {type} which will be replaced by the real values when delivering.

In order to setup **continuous delivery** to a **storage account**, you need to have an Azure Account and setup a storage account in the **Azure Portal**. You can create a **blob container** with the name of the the calculated container (based on containerName in the StorageContext) or you can add a setting called DeliverToStorage with a property called CreateContainerIfNotExist set to true for auto generation of the blob container. After this, create the secret value above manually or use the **New-ALGoStorageContext** from BcContainerHelper.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/7287e068-b2d5-4fc2-b428-d0ddd4ffa0e3) |
|-|

Now create an organizational secret called **StorageContext** with the secret value.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/8631d67f-d772-43f5-bae3-a0f342f89fdd) |
|-|

and add the deliverToStorage setting to the ALGOORGSETTINGS organizational variable:

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/9975ebbd-a98d-4bed-a57f-dae1c26546bd) |
|-|

When re-running **CI/CD** afterwards, you will see that continuous delivery is now setup for a storage account as well

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/2ec22ccd-76fa-4705-8e64-6b16a5867934) |
|-|

Checking the storage account using Storage Explorer reveals the new container and the new app.

| ![image](https://github.com/microsoft/AL-Go/assets/10775043/60db8d6e-7b4e-46cb-b426-aa1290b498aa) |
|-|

## AppSource
Continuous delivery to **AppSource** is supported by the AppSource template and will be included in the workshop later, but basically, creating a secret called **AppSourceContext** and setting a **AppSourceContinuousDelivery** to true in the repository settings file.

## NuGet
Still work-in-progress. Delivery to NuGet is supposed to be delivery to a NuGet feed, where your partners can get access to your apps or runtime packages. This section will be updated when we release delivery to NuGet in it's final version.

## Custom delivery
Custom delivery will be handled in an advanced part of this workshop later.

OK, so **CD** stands for **Continuous Delivery**, I thought it was **Continuous Deployment**? Well, it is actually both, so let's talk about **Continuous Deployment**...

---
[Index](Index.md)&nbsp;&nbsp;[next](ContinuousDeployment.md)
