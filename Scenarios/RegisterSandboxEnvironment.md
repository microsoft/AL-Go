# Register a customer sandbox environment for Continuous Deployment using S2S

*Prerequisites: A completed ["Add a test app to an existing project"](Scenarios/AddATestApp.md) scenario, a Microsoft Entra application registration, and an online sandbox environment called QA with the setup for S2S as specified in task 1 and 2 [here](https://go.microsoft.com/fwlink/?linkid=2217415&clcid=0x409) completed.*

> [!NOTE]
> For access to environments, environment secrets, and deployment branches in private or internal repositories, you must use GitHub Pro, GitHub Team, or GitHub Enterprise. (see [this](https://go.microsoft.com/fwlink/?linkid=2216857&clcid=0x409)).
> If you are running a free GitHub SKU, you can use the [environments](https://aka.ms/algosettings#environments) setting and a secret with a name of the environment followed by` _AuthContext` instead of GitHub environments and environment secrets.

1. On github.com, open **Settings** and **Environments** in your project. Click **New Environment** and specify the **name of the environment** you have created in your tenant and choose **Configure environment**

   ![New Environment](https://github.com/user-attachments/assets/df1ba43f-8adf-4400-87a9-a74c3d4f38f4)

1. Under **Environment secrets**, choose the **Add environment secret** action. Create a secret called **AUTHCONTEXT**, and enter a **COMPRESSED JSON** construct with 3 values: TenantID (where the environment lives), ClientID, and ClientSecret (from the pre-requisites), like:
   `{"TenantID":"<TenantID>","ClientID":"<theClientID>","ClientSecret":"<theClientSecret>"}`.

   ![image](https://github.com/user-attachments/assets/b36a92df-0f27-4c67-9670-02ef7cc68435)

> [!NOTE]
> The secret **NEEDS** to be compressed json and there should **NOT** be a newline after the secret value.

3. Navigate to **Actions**, select the **Publish To Environment** workflow and choose **Run workflow**. Enter **latest** in the **App version** field and the **name of your environment** or keep the * in the **environment to receive the new version** field. Click **Run workflow**.
   ![Publish To Environment](https://github.com/user-attachments/assets/9299009a-b429-477d-b1d0-c5bf96455a93)

> [!NOTE]
> The default app version is **current**, which refers to the latest release (current version in the market) of your app. Since we haven't released a version yet, you have to specify **latest**.

4. When the workflow completes, you can inspect the output of the workflow.

   ![Deploy To QA](https://github.com/user-attachments/assets/fbab7444-7b57-4b72-915a-992cdac88e8e)

1. And/or you can open the QA environment, navigate to Customers and see that your very own Hello World message appears.

   ![Hello World](https://github.com/user-attachments/assets/87d78254-4cc5-4353-9837-e1d186f27f33)

______________________________________________________________________

[back](../README.md)
