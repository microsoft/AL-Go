# Secrets

The behavior of AL-Go for GitHub is very much controlled by settings and secrets.

To learn more about the settings used by AL-Go for GitHub, please navigate to [Settings](settings.md).

## Where are the secrets defined

Secrets in GitHub can be defined on the Organizational level, on the repository level or on an environment.

**Organizational secrets** are defined on your GitHub organization and can be shared with the repositories in your organization. For the free GitHub plan, organizational secrets can only be shared with public repositories.

**Repository secrets** are defined on the individual repository and you can define any number of secrets on the repository. If you define a secret on the repository level with the same name as an organizational secret, shared with the repository, the repository secret overrides the organizational secret.

**Environment secrets** are defined underneath an environment and is only available to the workflow during deployment to this environment. For the free GitHub plan, environments (and secrets obviously) are only available on public repositories.

> [!NOTE]
> In AL-Go for GitHub you can also define your secrets in an Azure KeyVault, but you would still need to create one secret in GitHub called [Azure_Credentials](https://aka.ms/algosecrets#azure_credentials) to be able to access the Azure KeyVault.

## Important information about secrets (e.g. common mistakes...)

Please read the following topics carefully and make sure that you do not run into any of these common mistakes, which might cause some problems.

### Don't have secrets that are not secret

All secrets exposed to a repository will be masked (i.e. replaced with ***) in the workflow logs of that repository, ensuring that secret values are not exposed to the public. In GitHub, secrets are also not allowed to be transferred between jobs. If a variable transferred between two jobs contains a secret, you will see warnings like this in the output:

![image](https://github.com/microsoft/AL-Go/assets/10775043/b280360b-d3e8-47b9-8993-39b0de76d44a)

In this case, I have created a secret with the value "windows" and since the Initialization step transfers the githubRunner to the Build steps with the value "windows-latest", this will break AL-Go for GitHub.

So, don't have secrets that are not secrets as this might break core functionality in AL-Go for GitHub.

### Use compressed json

AL-Go for GitHub uses json structures for some secrets (like authentication contexts). AL-Go for GitHub will ensure that individual secret property values are masked in the log as well as the full json structure. When creating a json structure secret, it is important to use compressed json as GitHub will mask individual lines as well. This means that a non-compressed json structure will cause the curly bracket characters to be handled as secrets, breaking AL-Go for GitHub. In the logs you will see that the curly brackets are replaced with ***

![image](https://github.com/microsoft/AL-Go/assets/10775043/58bbc120-f36d-499d-8e6c-8cc87f55d918)

In this case, I created a secret with the value:

```
{
  "prop": "value"
}
```

So, don't have multi-line secrets, where individual lines are not secrets as this might break core functionality in AL-Go for GitHub.

### Only expose secrets necessary secrets to AL-Go repositories

If your GitHub organization might have many organizational secrets, please only allow access to the secrets actually used by your AL-Go for GitHub repository. If any of the secrets made available to your repository contains multi-line secrets or have secrets, where the value is not really a secret, it might break core functionality in AL-Go for GitHub.

# Secrets

## <a id="Azure_Credentials"></a>**Azure_Credentials** -> Connect to Azure

By creating a secret called Azure_Credentials you can give 



### Read secrets from KeyVault

Two security models for KeyVaults

### Sign an app

Keyvault must be premium SKU + how to change SKU using AZ CLI



## <a id="AuthContext"></a>**AuthContext** -> Deploy to an environment

Whenever AL-Go for GitHub is doing to deploy to an environment, it will need an AuthContext secret. The AuthContext secret can be provided underneath the environment in GitHub. If you are using a private repository in the free GitHub plan, you do not have environments. Then you can create an AuthContext secret in the repository. If you have multiple environments, you can create different AuthContext secrets by using the environment name followed by an underscore and AuthContext (f.ex. **QA_AuthContext**).

### Managed identity

Managed identities cannot be used for this as this is not an Azure resource

### Impersonation/RefreshToken

Specifying a RefreshToken allows AL-Go for GitHub to get access to impersonate the user who created the refresh token and act on behalf of that user on the scopes for which the refresh token was created. In this case, access is given to act as the user in Business Central.

Providing an AuthContext secret with a refreshtoken typically allows you to get access for 90 days. After the 90 days, you need to refresh the AuthContext secret with a new refreshToken. Note that anybody with the refreshToken can get access to call the API on behalf of the user, it doesn't have to be inside a workflow/pipeline.

Example: `{"TenantID":"69cb4a05-4ea8-482d-9f33-10fb5cf7db05","Scopes":"https://api.businesscentral.dynamics.com/","RefreshToken":"0.AUUAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_s6Eo4YOI","ClientID":"1950a258-227b-4e31-a9cf-717495945fc2"}`

### App Registration (Service to service authentication)

In order to use an App Registration for publishing apps to Business Central, you need to register the ClientId (Application Id) of is App Registration inside Business Central. This will create a user inside Business Central and you need to give the following permissions to that user: D365 AUTOMATION and EXTEN. MGT. - ADMIN. After this, there are two ways you can authenticate, either using Federated credential or using a Client Secret.

#### Federated credential

Using a federated credential, you need to register your GitHub repository in the App Registration under Certificates & Secrets. This registration will allow AL-Go for GitHub running in this repository to authenticate without the Client Secret stored. You still need to create a secret containing this information. The way this works is that AL-Go for GitHub will request an ID_TOKEN from GitHub as a proof of authenticity and use this when authenticating. This way, only workflows running in the specified branch/environment in GitHub will be able to authenticate.

Example:`{"TenantID":"69cb4a05-4ea8-482d-9f33-10fb5cf7db05","Scopes":"https://api.businesscentral.dynamics.com/","ClientID":"a26651f5-0e90-473c-b4f9-e96119aac8b8"}`

#### Client Secret

Under Certificates & Secrets in the App Registration, you can create a Client Secret, which you can specify in the AuthContext secret in AL-Go for GitHub. With the ClientId and ClientSecret, anybody can authenticate and perform actions as the connected user inside Business Central.

Example: `{"TenantID":"69cb4a05-4ea8-482d-9f33-10fb5cf7db05","Scopes":"https://api.businesscentral.dynamics.com/","ClientID":"a26651f5-0e90-473c-b4f9-e96119aac8b8","ClientSecret":"OPXxxxxxxxxxxxxxxxxxxxxxxabge"}`


## <a id="AppSourceContext"></a>**AppSourceContext** -> Deliver to AppSource

### Managed identity

Managed identities cannot be used for this as this is not an Azure resource

### App Registration (Service to service authentication)

#### Federated credential

#### Client Secret

## <a id="StorageContext"></a>**StorageContext** -> Deliver to storage

In AL-Go for GitHub, the Storage Context can be specified in 5 different ways, 5 different authentication mechanism towards an Azure Storage Account.

### Managed Identity/Federated credential

As a storage account is an Azure resource, we can use managed identities. Managed identities are like virtual users in Azure, using federated credentials for authentication. Using a federated credential, you need to register your GitHub repository in the managed identity under Settings -> Federated Credentials. The way this works is that AL-Go for GitHub will request an ID_TOKEN from GitHub as a proof of authenticity and use this when authenticating. This way, only workflows running in the specified branch/environment in GitHub will be able to authenticate.

Example: `{"storageAccountName":"fkteststorage","clientId":"08b6d80c-68cf-48f9-a5ff-b054326e2ec3","tenantId":"72f988bf-86f1-41af-91ab-2d7cd011db47","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### App Registration/Federated credential

Am App Registration with federated credential is harder to setup than a managed identity, but just as secure.

Example: `{"storageAccountName":"fkteststorage","clientId":"a26651f5-0e90-473c-b4f9-e96119aac8b8","tenantId":"72f988bf-86f1-41af-91ab-2d7cd011db47","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### App Registration/Client Secret

Client

Example: `{"storageAccountName":"fkteststorage","clientId":"a26651f5-0e90-473c-b4f9-e96119aac8b8","clientSecret":"OPXxxxxxxxxxxxxxxxxxxxxxxabge","tenantId":"72f988bf-86f1-41af-91ab-2d7cd011db47","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### storageAccountName/sastoken

A sastoken can be limited in time....

Example: `{"storageAccountName":"fkteststorage","sastoken":"sv=2022-11-02&ss=b&srt=sco&sp=rwdlaciytf&se=2024-08-06T20:22:08Z&st=2024-04-06T12:22:08Z&spr=https&sig=IZyIf5xxxxxxxxxxxxxxxxxxxxxtq7tj6b5I%3D","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### storageAccountName/storageAccountKey

Using storageAccount Name and Key is by far the most unsecure way of authenticating to an Azure Storage Account. If ever compromised, people can do anything with these credentials, until the storageAccount key is cycled.

Example: `{"storageAccountName":"fkteststorage","storageAccountKey":"JHFZErCyfQ8xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxStj7AHXQ==","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"} `

## <a id="NuGetContext"></a>**NuGetContext** -> Deliver to NuGet

Example: `{"token":"ij7xxxxxxxxxxxxxxxxxxxxp7di52ta","serverUrl":"https://pkgs.dev.azure.com/freddydk/apps/_packaging/MyApps/nuget/v3/index.json"}`

## <a id="GitHubPackagesContext"></a>**GitHubPackagesContext** -> Deliver to GitHub Packages

Example: `{"token":"ghp_NDdI2ExxxxxxxxxxxxxxxxxAYQh","serverUrl":"https://nuget.pkg.github.com/freddydkorg/index.json"}`

test