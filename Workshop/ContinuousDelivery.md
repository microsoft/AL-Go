# Continuous Delivery
Continuous Delivery is where AL-Go delivers your apps to whereever you like.

Currently, the following targets are supported:
- GitHub Packages
- Storage
- AppSource
- Custom

This workshop has already described how to setup continuous delivery for GitHub Packages [here](Dependencies2.md).

## Storage
Setting up continuous delivery to a storage account is done in the same mechanism as we did with GitHub Packages.

Create an organizational secret called **StorageContext**. The format of the secret needs to be **compressed JSON**, containing 4 values: **StorageAccountName**, **StorageAccountKey**, **ContainerName** and **BlobName**. Example:
```
{"StorageAccountName":"accountnanme","StorageAccountKey":"HOaRhoNXXX==","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}
```

ContainerName and BlobName can contain "variable", like {project}, {version} and {type} which will be replaced by the real values when delivering.

In order to setup **continuous delivery** to a **storage account**, you need to have an Azure Account and setup a storage account in the **Azure Portal**, and create a **blob container** with the name of the the calculated container (based on containerName in the StorageContext). After this, create the secret above manually or use the **New-ALGoStorageContext** from BcContainerHelper.

| ![image](https://user-images.githubusercontent.com/10775043/232289028-e73c8395-b39d-49d7-9e5b-52eb8e8c8db4.png) |
|-|

and when running **CI/CD** afterwards, you will see that continuous delivery is now setup for a storage account as well

| ![image](https://user-images.githubusercontent.com/10775043/232289443-9109d260-8009-470f-950a-b8960ab2a44e.png) |
|-|

## AppSource
Continuous delivery to **AppSource** is supported by the AppSource template and will be included in the workshop later, but basically, creating a secret called **AppSourceContext** and setting a **AppSourceContinuousDelivery** to true in the repository settings file.

## Custom delivery
Custom delivery will be handled in an advanced part of this workshop later.

OK, so **CD** stands for **Continuous Delivery**, I thought it was **Continuous Deployment**? Well, it is both, so let's talk about **Continuous Deployment**...

---
[Index](Index.md)&nbsp;&nbsp;[next](ContinuousDeployment.md)
