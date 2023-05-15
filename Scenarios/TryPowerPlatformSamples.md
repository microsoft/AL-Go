# (Preview) Try one of the Business Central and Power Platform samples

The easiest way to get started with Business Central and Power Apps is to find one of our sample apps:

- [Take Order](https://github.com/BusinessCentralDemos/TakeOrder)
- [Warehouse helper](https://github.com/BusinessCentralDemos/WarehouseHelper) 

From the sample app repository, you have two options:

1. **Fork the Repository**: This gives you access to all the source code for the Power Platform solution and AL extension. Follow the steps in the  [Power Platform repository setup guide](./SetupPowerPlatform.md) to get started. Once set up, you can easily publish the latest changes to your environment.

    *NOTE: The first time you import the solution into your environment, you need to set up the Business Central connection reference authentication. See an example in the screen shot below* 
    ![Screen shot from Power Apps showing how to set up a the Business Central connection reference](images/p3.png)

<br>
<br>

2. **Manual Deployment**: Alternatively, you can manually deploy the AL extension and Power Platform solution package. You can find the files under the repository release artifacts. 
  Please note that if you choose this method, you have to manually update the Business Central data references within the Power App and Power Automate flow components.

    *Note: You update the connection reference by removing the existing connection and adding a new one from your environment. See an example in the screen shot below*
    ![Screen shot from Power Apps showing how to set up a the Business Central connection reference](images/p4.png)

Choose the method that suits you best and get started with exploring the capabilities of Business Central and Power Platform!

