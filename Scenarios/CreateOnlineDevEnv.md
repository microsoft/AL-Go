# #8 Create Online Development Environment from VS Code
*Prerequisites: A completed [scenario 7](UseAzureKeyVault.md)*

1. Open your **App1** project in VS Code, open the **cloudDevEnv.ps1** in your **.AL-Go** folder and run the script.
![Cloud DevEnv](https://github.com/microsoft/AL-Go/assets/10775043/adfafea6-4136-4120-95e7-45e7313cc67d)
1. The script will ask for an **environment name** if it isn’t specified and it will ask whether you want to reuse or **recreate** the environment if it already exists. After this the script will need access to the **admin center API** and will initiate a **device code login** for this purpose.
![Cloud DevEnv](https://github.com/microsoft/AL-Go/assets/10775043/ce042a0a-0a91-481f-8752-4fa40ec78424)
1. Open [https://aka.ms/devicelogin](https://aka.ms/devicelogin) and paste in the **code provided**, sign in and accept that you are trying to sign in with PowerShell.
![Cloud DevEnv](https://github.com/microsoft/AL-Go/assets/10775043/751bb507-1a5e-436f-8a2a-1acdd53c33ab)
1. Wait for the script to finish. All apps are compiled and published to the online environment using the development scope and **VS Code is ready for RAD development**
![Cloud DevEnv](https://github.com/microsoft/AL-Go/assets/10775043/20c5848a-3238-4fed-a1f2-36dd027884cd)
1. Modify your app, press **F5** and select the **Cloud Sandbox** with your new name.
![Cloud DevEnv](https://github.com/microsoft/AL-Go/assets/10775043/7cebf477-28ff-4746-9004-c5075015b7c8)
1. Your online environment will have your app changes.
![Cloud DevEnv](https://github.com/microsoft/AL-Go/assets/10775043/6c5b5ebd-c46e-41e6-bc5e-e25344ecb3ae)
1. The `launch.json` file will be updated with your new environment in VS Code. You can decide whether you want to check-in the changes to the repo or only use this locally.

---
[back](../README.md)
