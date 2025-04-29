# Register a customer production environment for Manual Deployment

*Prerequisites: A completed [scenario 4](CreateRelease.md), an online production environment setup for S2S as specified in task 2 here [Using Service to Service Authentication - Business Central | Microsoft Docs](https://go.microsoft.com/fwlink/?linkid=2217415&clcid=0x409), using the same Microsoft Entra application registration as scenario 3*

> [!NOTE]
> For access to environments, environment secrets, and deployment branches in private or internal repositories, you must use GitHub Pro, GitHub Team, or GitHub Enterprise. (see [this](https://go.microsoft.com/fwlink/?linkid=2216857&clcid=0x409)). We are considering adding a secondary option for listing environments.

1. Following the process in step 3, you can add an environment to the GitHub repository under settings called **MYPROD (Production)**, which maps to a production environment called **MYPROD**. Remember the **AUTHCONTEXT** Secret. Apps will NOT be deployed to production environments from the CI/CD pipeline, by adding the **(Production)** tag, the environment will be filtered out already during the **Analyze** phase. You need to run the **Publish To Environment** workflow to publish the apps. Leave the App version as **current**, which means that the **latest released bits** are published to **MYPROD**.
   ![Publish to MYPROD](https://github.com/user-attachments/assets/fdb05510-2785-483a-b2f3-98a2fe36bfc4)
1. When running the **Publish to Environment** workflow, you should see that the app is deployed to the **MYPROD** environment only.
   ![MYPROD](https://github.com/user-attachments/assets/04dab8af-57b4-4bc3-a0c2-6e6869d8df34)

> [!NOTE]
> If your Business Central environment name contains spaces or special characters, you might need to map your GitHub environment name to your Business Central environment name using the DeployTo setting with an EnvironmentName setting called DeployTo.

```json
"DeployTo<GitHubEnvironmentName>": {
    "EnvironmentName":  "<Business Central Environment Name>"
}
```

______________________________________________________________________

[back](../README.md)
