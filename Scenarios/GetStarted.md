# #1 Create a new per-tenant extension (like AL Go) and start developing in VS Code
*Prerequisites: A GitHub account, VS-Code (with AL and PowerShell extensions installed), and Docker installed locally*

1. Navigate to [https://github.com/microsoft/AL-Go-PTE](https://github.com/microsoft/AL-Go-PTE) and choose **Use this template**
![Use this template](https://github.com/microsoft/AL-Go/assets/10775043/b808352c-c293-4ed3-b460-40e7b0ec36e9)
1. Enter **app1** as repository name, select Public or Private and select **Create Repository from template**
1. Select **Actions** -> **Create a new app** -> **Run workflow**
![Run workflow](https://github.com/microsoft/AL-Go/assets/10775043/6c1ac9c3-14c2-4917-a31a-d94e5bb7bd66)
1. Enter **Name**, **Publisher**, **ID range** and specify **Y** in **Direct COMMIT** and choose **Run workflow**.
1. When the workflow is complete, select **< > Code** in the top bar
1. Choose the **Code** button and copy the **https Clone Url** (in this picture: *https://github.com/freddydk/App1.git*)
![Clone](https://github.com/microsoft/AL-Go/assets/10775043/84b92edb-72b8-4444-908c-0c6f6bc2b7f7)
1. Start **VS Code**, press **Ctrl+Shift+P** and select **Git Clone**, paste the clone URL and select a folder in which you want to clone the directory.
1. **Open the cloned repository** and **open the workspace** when VS Code asks you (or do it manually)
1. In the **.AL-Go** folder, choose the **localDevEnv.ps1** script and Run the PowerShell script.
![LocalDevEnv](https://github.com/microsoft/AL-Go/assets/10775043/fded935a-b529-4ade-8daa-bbe7e37726b8)
1. Answer the questions asked about container name, authentication mechanism, credentials and select none for license file. The script might show a dialog asking for permissions to run docker commands, select **Yes** in this dialog. Wait for completion of the script.
![LocalDevEnv Done](https://github.com/microsoft/AL-Go/assets/10775043/6d88b2b8-3198-4c4e-8f4e-292178fa2e9f)
1. In VS Code, press **Ctrl+Shift+P** and **clear the credentials cache**.
1. Open the **HelloWorld.al** file, modify the string and press **F5**. Depending on authentication selected VS Code might ask for the credentials you provided earlier.
1. Login to **Business Central** and your **very own world** opens up!
![Very own world](https://github.com/microsoft/AL-Go/assets/10775043/02037442-b604-4ea7-9ec4-256a5fafad4a)
1. Back in **VS Code**, you will see that in addition to your changes in HelloWorld.al, the launch.json was also modified with the information about the local environment. **Stage your changes**, **commit** and **push**
![Launch.json](https://github.com/microsoft/AL-Go/assets/10775043/b71daf76-3166-4d33-8724-160ac3f60e31)
1. Back on github.com, investigate your **Workflows**.
![Workflows](https://github.com/microsoft/AL-Go/assets/10775043/aaef1edb-9e42-4de4-bec2-e21b2da1ae61)
1. When the build is done, inspect the **Build summary** (no test app)
![Build Summary](https://github.com/microsoft/AL-Go/assets/10775043/f6a25fff-eef0-433c-84b0-e12b0b62008a)
1. Inspect the workflow run by choosing the **build job**, expanding the **Run Pipeline** section and the **Compiling apps** subsection
![Inspect](https://github.com/microsoft/AL-Go/assets/10775043/20a6da2b-33fe-4ebc-ad05-786e7700eeb6)

---
[back](../README.md)
