# [PREVIEW] Try one of the Business Central and Power Platform samples

The easiest way to get started with Business Central and Power Apps is to find one of our sample apps:

- [Take Order](https://github.com/microsoft/bcsamples-takeorder)
- [Warehouse helper](https://github.com/microsoft/bcsamples-warehousehelper) 

> **NOTE:** Other samples might be available here: [https://github.com/topics/bcsamples](https://github.com/topics/bcsamples).

From the sample app repository, you have two options:


## Manual Installation
If you just want to try the apps and not the ALM functionality, follow these steps:

1. In the App repository, find the latest release and download the Power platform solution and the Business Central extension zip files. *Note:* You need to unzip the files to access the actual extension and solution file.
![Screen shot from showing where the release artifacts are located](images/p4.png)

2. Upload the Business Central extension to your Business Central environment.

3. (Optional) Open the sample page to generate demo data.

4. Import the Power Platform solution to your Power Platform environment. You will be asked to add a Business Central connection if your environment does not have one. Follow the steps in the wizard to add it.
    > **Note:** You might receive a warning about the imported flow. This is expected and will be addressed in a subsequent step.

5. Update the flow so it is pointing to your Business Central environment and company. Clear the current values and use the dropdown to select your settings.
![Screen shot from Power Automate showing where to update the Business Central connection reference](images/p5.png)

6. Update the Power App data sources so they are pointing to your Business Central environment. If you hover over the data source, you can see the connection information under the Dataset name. Delete the connections and add a new one pointing to your environment and company using the "+ Add data" button.
![Screen shot from Power Apps showing where to update the Business Central connection reference](images/p6.png)


## Fork the Repository

This gives you access to all the source code for the Power Platform solution and AL extension and the ALM infrastructure. Follow the steps in the  [Power Platform repository setup guide](./SetupPowerPlatform.md) to get started. Once set up, you can easily publish the latest changes to your environment.

> **NOTE:** The first time you import the solution into your environment, you need to set up the Business Central connection reference authentication. See an example in the screen shot below

![Screen shot from Power Apps showing how to set up a the Business Central connection reference](images/p3.png)



Choose the method that suits you best and get started with exploring the capabilities of Business Central and Power Platform!

---
[back](../README.md)
