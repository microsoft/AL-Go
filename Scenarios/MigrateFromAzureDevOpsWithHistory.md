# #B Migrate a repository from Azure DevOps to AL-Go for GitHub with history
*This walkthrough explains how to migrate a repository from Azure DevOps to AL-Go for GitHub **while preserving the full commit history**. As a sample, I will use a repository, which was setup using the CI/CD Hands On Lab, including scripts and pipelines from this.*

*If you do not want to preserve the full commit history, you should use [Scenario A](MigrateFromAzureDevOpsWithoutHistory.md) or [Scenario 11](SetupCiCdForExistingAppSourceApp.md)*

***Note: This walkthrough will leave your existing Azure DevOps repository untouched and you can decide to keep working in that if you like.***

1. Start out by navigating to your **Azure DevOps** repository. Click the **Clone** button and click **Generate Git Credentials**.
![Azure DevOps](https://github.com/microsoft/AL-Go/assets/10775043/59b623eb-56da-4821-8869-b27a34954597)
1. Copy the **Password** to the clipboard, navigate to **GitHub**, login and click the small **+** menu in the top right corner and select **Import repository**.
![files](https://github.com/microsoft/AL-Go/assets/10775043/9b8eb461-e03a-4c77-b0d2-be5bbb2ea25b)
1. Enter the **GIT URL** to the Azure DevOps repository, choose the owner+name of the new GitHub repository and specify privacy level. Click **Begin Import**.
![createrepo](https://github.com/microsoft/AL-Go/assets/10775043/2f94e677-f713-4771-953a-16d7f1a8a0aa)
1. If your GIT repository requires **authentication**, you will be asked to provide this (the password you copied to the clipboard).
![auth](https://github.com/microsoft/AL-Go/assets/10775043/a3c16e8d-0ae4-43c0-99d1-4df57acf8551)
1. After GitHub is done importing your repo, you can **navigate to the repo**.
![importdone](https://github.com/microsoft/AL-Go/assets/10775043/7f7a6d5a-4d3b-4e47-8ac2-426dfd1a3c39)
1. In the new GitHub repository, you might see different messages about branches and PRs. This is because GitHub has imported everything. Ignore this for now. Click the **<> Code** button and copy the git address to the clipboard.
![newrepo](https://github.com/microsoft/AL-Go/assets/10775043/2089bcc3-8aa3-4582-be9d-3ce77364198a)
1. Open **VS Code**, press **Ctrl+Shift+P**, select **Git Clone** and paste your git URL into the address bar. Select a location, clone and open the repo and open the Repo in VS Code.
![clone](https://github.com/microsoft/AL-Go/assets/10775043/4d91c31d-1aee-4fad-990e-73a075e69026)
1. Delete the files and folders that are not needed in AL-Go for GitHub (including **.github**, **.azureDevOps**, **.pipelines** and **scripts** folders), leaving only your **apps**, your **test apps** and other files you want to preserve.
![delete](https://github.com/microsoft/AL-Go/assets/10775043/e8d21772-30dc-448a-8892-92a66c7c36e6)
1. Now, download the AL-Go template needed, either the [PTE template](https://github.com/microsoft/AL-Go-PTE/archive/refs/heads/main.zip) or the [AppSource Template](https://github.com/microsoft/AL-Go-AppSource/archive/refs/heads/main.zip). Unpack the .zip file and open the unpacked template files.
![templatefiles](https://github.com/microsoft/AL-Go/assets/10775043/7539c845-b696-4347-8b2f-d51d6be2ebfa)
1. Drag the needed files and folders from the unpacked files file into VS Code (at a minimum the .AL-Go folder and the .github folder) and select to **Copy the folders**.
![newfiles](https://github.com/microsoft/AL-Go/assets/10775043/edd24801-73cd-4ad4-9fc6-5d2cd80ac6c8)
1. Modify any settings necessary for the app. Typical settings you might need to modify are:
    - appFolders, see https://aka.ms/algosettings#appfolders
    - testFolders, see https://aka.ms/algosettings#testfolders
    - appSourceMandatoryAffixes, see https://aka.ms/algosettings#appSourceMandatoryAffixes
    - enableAppSourceCop, see https://aka.ms/algosettings#enableAppSourceCop
    - enablePerTenantExtensionCop, see https://aka.ms/algosettings#enablePerTenantExtensionCop
    - enableCodeCop, see https://aka.ms/algosettings#enableCodeCop
    - enableUICop, see https://aka.ms/algosettings#enableUICop
    - rulesetFile, see https://aka.ms/algosettings#rulesetFile
    - enableExternalRulesets, see https://aka.ms/algosettings#enableExternalRulesets
    - runNumberOffset, see https://aka.ms/algosettings#runNumberOffset

    Also, if you are migrating an AppSource App, you will need to create a secret called LicenseFileUrl, which should contain a secure direct download URL to your license file, as mentioned [here](SetupCiCdForExistingAppSourceApp.md).

    Finally, if you want AL-Go for GitHub to digitally sign your file, you need to create two secrets in the repository (or in the organization) called **CodeSignCertificateUrl** and **CodeSignCertificatePassword**, being a secure direct download URL to your PFX certificate and the PFX password for the certificate.

    See a list of all settings [here](settings.md).

1. In VS Code, in the Source Control area, **Add** all changed files, **Commit** the changes and press **Sync Changes** to push to GitHub.
![commit](https://github.com/microsoft/AL-Go/assets/10775043/55afdd6f-e401-4542-9029-652f5ce7a3e9)
1. Navigate back to your repository on GitHub. See that your files have been uploaded. Click **Settings** -> **Actions** -> **General**, select **Allow all actions and reusable workflows** and click **Save**.
![upload](https://github.com/microsoft/AL-Go/assets/10775043/4f717190-5e5f-45e9-a187-186ac45be590)
1. Click **Actions**, select the **CI/CD** workflow and click **Run workflow** to manually run the CI/CD workflow.
![cicd](https://github.com/microsoft/AL-Go/assets/10775043/ec7f76b1-2eb9-42fe-91a3-c0170c796d3c)
1. Open the running workflow to see **status and summary** and **wait for the build to complete**.
![success](https://github.com/microsoft/AL-Go/assets/10775043/8a1fcd6d-0a8d-4bbc-bb97-51a4c48e537a)
1. Scroll down to see the artifacts and the **test results**
![testresults](https://github.com/microsoft/AL-Go/assets/10775043/7267a1a7-7afe-495f-8100-474fb8db9499)
1. Navigate to **Code** and click **Commits** to see the history and all your commits.
![history](https://github.com/microsoft/AL-Go/assets/10775043/c10ea3b3-2b1b-486d-9727-6b91b7bc3834)

---
[back](../README.md)
