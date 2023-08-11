# #10 Set up CI/CD for an existing per-tenant extension (BingMaps)
*Prerequisites: A GitHub account.
We will use the BingMaps sample app, which can be found on GitHub in the [Business Central BingMaps.PTE repo](https://github.com/BusinessCentralApps/BingMaps.PTE). Copy the following URL (a direct download of the latest released app file from BingMaps sample) to the clipboard: [https://businesscentralapps.blob.core.windows.net/bingmaps-pte/latest/bingmaps-pte-apps.zip](https://businesscentralapps.blob.core.windows.net/bingmaps-pte/latest/bingmaps-pte-apps.zip) – you can also download the .zip file and see the content of it.

1. Navigate to [https://github.com/microsoft/AL-Go-PTE](https://github.com/microsoft/AL-Go-PTE) and then choose **Use this template**.
![Use this template](https://github.com/microsoft/AL-Go/assets/10775043/b4e32467-723d-434e-8c0a-45c6254699b4)
1. Enter **app2** as repository name and select **Create Repository from template**.
1. Under **Actions** select the **Add existing app or test app** workflow and choose **Run workflow**.
1. In the **Direct Download URL** field, paste in the direct download URL of the BingMaps sample from above.
1. When the workflow is complete, inspect the **Pull request**.
![Pull Request](https://github.com/microsoft/AL-Go/assets/10775043/a02cdef9-b3f7-486a-be32-a19a3f56525d)
1. Merge the pull request. The **CI/CD** workflow will kick off.
![CI/CD](https://github.com/microsoft/AL-Go/assets/10775043/58ab0a72-4b81-4a52-814f-a0984d7154de)
1. After the workflow completes, you can investigate the output and see that everything works.
![Success](https://github.com/microsoft/AL-Go/assets/10775043/d7806af4-822d-43ea-8103-dd7c69e8fd64)
1. Use [scenario 3](RegisterSandboxEnvironment.md), [scenario 4](CreateRelease.md), and [scenario 5](RegisterProductionEnvironment.md) to set up customer environments, publish and test the app.

---
[back](../README.md)
