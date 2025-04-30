# Create a new per-tenant extension (like AL:Go in VS Code) and start developing in VS Code

*Prerequisites: A GitHub account, VS-Code (with AL, git and PowerShell extensions installed), and Docker installed locally*

1. Navigate to [https://github.com/microsoft/AL-Go-PTE](https://github.com/microsoft/AL-Go-PTE), choose **Use this template** and select **Create a new repository**.

   ![Use this template](https://github.com/user-attachments/assets/78acdaf2-7144-4a58-88da-933a875e6c87)

1. Enter **app1** as repository name, select Public or Private and select **Create Repository**

   ![Create a new repository](https://github.com/user-attachments/assets/f82d3387-dc81-41d2-8fd5-6fc8ff78c574)

1. In your new repository, select **Actions** -> **Show more workflows...**, **Create a new app** -> **Run workflow**
1. Enter **Name**, **Publisher**, **ID range**, select **Direct Commit** and choose **Run workflow**.

   ![Create a new app](https://github.com/user-attachments/assets/3a955943-80cc-48a9-9958-d8c2b3132ac5)

1. Wait for the workflow to complete

   ![Wait for completion](https://github.com/user-attachments/assets/b9e463b4-c282-45e6-94fc-b0d52fd23270)

1. When the workflow is complete, select **< > Code** in the top bar and see that your repository now contains a folder called **app1**

   ![app1](https://github.com/user-attachments/assets/b119b33a-7ab2-4605-91d6-669ce4b71fc7)

1. Choose the **Code** button and copy the **https Clone Url** (in this picture: *https://github.com/freddyk-temp/app1.git*)

   ![Copy Url](https://github.com/user-attachments/assets/469c4f1b-9991-40e9-88a3-f306819845d6)

1. Start **VS Code**, press **Ctrl+Shift+P** and select **Git Clone**, paste the clone URL and select a folder in which you want to clone the directory.

   ![Clone](https://github.com/user-attachments/assets/48062828-b41d-4ff4-943b-ceb3a9b58fe3)

1. **Open the cloned repository** and **open the workspace** when VS Code asks you (or do it manually)

> [!NOTE]
> You can rename the `al.code-workspace` file to `<anothername>.code-workspace` to be able to better distinguish the workspaces.

10. In the **.AL-Go** folder, choose the **localDevEnv.ps1** script and Run the PowerShell script.

    ![LocalDevEnv](https://github.com/user-attachments/assets/1b5f9304-bae0-4aba-a72d-358c266a5c94)

1. Answer the questions asked about container name, authentication mechanism, credentials and select none for license file. The script might show a dialog asking for permissions to run docker commands, select **Yes** in this dialog. Wait for completion of the script.

   ![LocalDevEnv done](https://github.com/user-attachments/assets/9fd335d7-34cb-413e-9d33-3664fee93e80)

1. In VS Code, press **Ctrl+Shift+P** and **clear the credentials cache**.
1. Open the **HelloWorld.al** file, modify the string and press **F5**. Depending on authentication selected VS Code might ask for the credentials you provided earlier.

   ![Modify Hello World](https://github.com/user-attachments/assets/87826e3b-1717-4f19-a69b-b61bf7092141)

1. Login to **Business Central**, navigate to Customers and your **very own Hello World** opens up!

   ![My very own Hello world](https://github.com/user-attachments/assets/ffb0540b-a80e-4186-a280-9ae3a509c89c)

1. Back in **VS Code**, you will see that in addition to your changes in HelloWorld.al, the launch.json was also modified with the information about the local environment. **Stage your changes**, **commit** and **sync** your changes.

   ![launch.json](https://github.com/user-attachments/assets/e2baf584-12bf-4bd9-ab68-9d1210bab70c)

1. Back on github.com, click **Actions** and investigate your workflows.

   ![Actions](https://github.com/user-attachments/assets/505f63f0-d782-409b-8fd2-be3a9ea969cc)

1. When the build is done, click the build and inspect the **Build summary**

   ![Build Summary](https://github.com/user-attachments/assets/688d814b-758f-4d49-a15a-02700f595a24)

1. Inspect the workflow run by choosing the **build job**, expanding the **Run Pipeline** section and the **Compiling apps** subsection

   ![Inspect](https://github.com/user-attachments/assets/6db47088-bc21-4613-bd0f-609117ee2698)

______________________________________________________________________

[back](../README.md)
