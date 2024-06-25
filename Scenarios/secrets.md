# Secrets

The behavior of AL-Go for GitHub is very much controlled by settings and secrets.

To learn more about the settings used by AL-Go for GitHub, please navigate to [Settings](settings.md).

## Where are the secrets defined

Secrets in GitHub can be defined on the Organizational level, on the repository level or on an environment.

**Organizational secrets** are defined on your GitHub organization and can be shared with the repositories in your organization. For the free GitHub plan, organizational secrets can only be shared with public repositories.

**Repository secrets** are defined on the individual repository and you can define any number of secrets on the repository. If you define a secret on the repository level with the same name as an organizational secret, shared with the repository, the repository secret overrides the organizational secret.

**Environment secrets** are defined underneath an environment and is only available to the workflow during deployment to this environment. For the free GitHub plan, environments (and secrets obviously) are only available on public repositories.

See also [https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#about-secrets](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#about-secrets).

> \[!NOTE\]
> In AL-Go for GitHub you can also define your secrets in an Azure KeyVault, but you would still need to create one secret in GitHub called [Azure_Credentials](https://aka.ms/algosecrets#azure_credentials) to be able to access the Azure KeyVault.

## Important information about secrets (e.g. common mistakes...)

Please read the following topics carefully and make sure that you do not run into any of these common mistakes, which might cause some problems.

### Don't have secrets that are not secret

All secrets exposed to a repository will be masked (i.e. replaced with \*\*\*) in the workflow logs of that repository, ensuring that secret values are not exposed to the public. In GitHub, secrets are also not allowed to be transferred between jobs. If a variable transferred between two jobs contains a secret, you will see warnings like this in the output:

![image](https://github.com/microsoft/AL-Go/assets/10775043/b280360b-d3e8-47b9-8993-39b0de76d44a)

In this case, a secret with the value "windows" have been created and since the Initialization step transfers the githubRunner to the Build steps with the value "windows-latest", this will break AL-Go for GitHub.


So, don't have secrets that are not secrets as this might break core functionality in AL-Go for GitHub.

### Use compressed JSON


AL-Go for GitHub uses json structures for some secrets (like authentication contexts). AL-Go for GitHub will ensure that individual secret property values are masked in the log as well as the full json structure. When creating a json structure secret, it is important to use compressed json as GitHub will mask individual lines as well. This means that a non-compressed json structure will cause the curly bracket characters to be handled as secrets, breaking AL-Go for GitHub. In the logs you will see that the curly brackets are replaced with \*\*\*

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

By creating a secret called Azure_Credentials you can give your GitHub repository access to an Azure KeyVault, from which you can read secrets and use for managed signing of your apps. You can use a managed identity or an app registration (service to service) for authentication.

> \[!NOTE\]
> In order to use a KeyVault for signing apps, it needs to be a premium SKU KeyVault. You can use this command to modify an existing KeyVault: `az keyvault update --set properties.sku.name=premium --name <KeyVaultName> --resource-group <ResourceGroupName>`

A KeyVault can be setup for two different security models: Role Based Access Control (RBAC = recommended) and Vault Access Policy. In order for AL-Go for GitHub to use the KeyVault, the following roles/permissions needs to be assigned to the app registration or Managed Identity on which the authentication is performed:

| Security Model | Read Secrets | Sign Apps |
| :-- | :-- | :-- |
| Role Based Access Control | Role: Key Vault Secrets User | Roles: Key Vault Crypto User + Key Vault Certificate User |
| Vault Access Policy | Secret permissions: Get, List | Cryptographic Operations: Sign + Certificate permissions: Get |

### Managed Identity or App Registration

Whether you use a managed identity or an app registration for authentication, you need to assign the right permissions / roles to its Client Id (Application Id). For managed identities, the only authentication mechanism supported is federated credentials. For an app registration you can use federated credentials or a client Secret.

#### Federated credential

Using a federated credential, you need to register your GitHub repository in your managed identity under settings -> federated credentials or in the app registration under Certificates & Secrets. This registration will allow AL-Go for GitHub running in this repository to authenticate without the Client Secret stored. You still need to create a secret containing the clientId and the tenantId. The way this works is that AL-Go for GitHub will request an ID_TOKEN from GitHub as a proof of authenticity and use this when authenticating. This way, only workflows running in the specified branch/environment in GitHub will be able to authenticate.

Example: `{"keyVaultName":"MyKeyVault","clientId":"ed79570c-0384-4826-8099-bf0577af6667","tenantId":"c645f7e7-0613-4b82-88ca-71f3dbb40045"}`

#### ClientSecret

ClientSecret can only be used using an app registration. Under Certificates & Secrets in the app registration, you need to create a Client Secret, which you can specify in the AuthContext secret in AL-Go for GitHub. With the ClientId and ClientSecret, anybody can authenticate and perform actions as the connected user inside Business Central.

Example: `{"keyVaultName":"MyKeyVault","clientId":"d48b773f-2c26-4394-8bd2-c5b64e0cae32","clientSecret":"OPXxxxxxxxxxxxxxxxxxxxxxxabge","tenantId":"c645f7e7-0613-4b82-88ca-71f3dbb40045"}`

With this setup, you can create a setting called `keyVaultCodesignCertificateName` containing the name of the imported certificate in your KeyVault in order for AL-Go for GitHub to sign your apps.

## <a id="AuthContext"></a>**AuthContext** -> Deploy to an environment

Whenever AL-Go for GitHub is doing to deploy to an environment, it will need an AuthContext secret. The AuthContext secret can be provided underneath the environment in GitHub. If you are using a private repository in the free GitHub plan, you do not have environments. Then you can create an AuthContext secret in the repository. If you have multiple environments, you can create different AuthContext secrets by using the environment name followed by an underscore and AuthContext (f.ex. **QA_AuthContext**).

### Managed identity

Managed identities cannot be used for this as this is not an Azure resource

### Impersonation/RefreshToken

Specifying a RefreshToken allows AL-Go for GitHub to get access to impersonate the user who created the refresh token and act on behalf of that user on the scopes for which the refresh token was created. In this case, access is given to act as the user in Business Central.

Providing an AuthContext secret with a refreshtoken typically allows you to get access for 90 days. After the 90 days, you need to refresh the AuthContext secret with a new refreshToken. Note that anybody with the refreshToken can get access to call the API on behalf of the user, it doesn't have to be inside a workflow/pipeline.

Example: `{"tenantId":"d630ce39-5a0c-41ec-bf0d-6758ad558f0c","scopes":"https://api.businesscentral.dynamics.com/","RefreshToken":"0.AUUAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_s6Eo4YOI","clientId":"1950a258-227b-4e31-a9cf-717495945fc2"}`

### App Registration (Service to service authentication)

In order to use an app registration for publishing apps to Business Central, you need to register the ClientId (Application Id) of is app registration inside Business Central. This will create a user inside Business Central and you need to give the following permissions to that user: D365 AUTOMATION and EXTEN. MGT. - ADMIN. After this, there are two ways you can authenticate, either using Federated credential or using a Client Secret.

#### Federated credential

Using a federated credential, you need to register your GitHub repository in the app registration under Certificates & Secrets. This registration will allow AL-Go for GitHub running in this repository to authenticate without the Client Secret stored. You still need to create a secret containing this information. The way this works is that AL-Go for GitHub will request an ID_TOKEN from GitHub as a proof of authenticity and use this when authenticating. This way, only workflows running in the specified branch/environment in GitHub will be able to authenticate.

Example:`{"tenantId":"d630ce39-5a0c-41ec-bf0d-6758ad558f0c","scopes":"https://api.businesscentral.dynamics.com/","clientId":"d48b773f-2c26-4394-8bd2-c5b64e0cae32"}`

#### Client Secret

Under Certificates & Secrets in the app registration, you can create a Client Secret, which you can specify in the AuthContext secret in AL-Go for GitHub. With the ClientId and ClientSecret, anybody can authenticate and perform actions as the connected user inside Business Central.

Example: `{"tenantId":"d630ce39-5a0c-41ec-bf0d-6758ad558f0c","scopes":"https://api.businesscentral.dynamics.com/","clientId":"d48b773f-2c26-4394-8bd2-c5b64e0cae32","clientSecret":"OPXxxxxxxxxxxxxxxxxxxxxxxabge"}`

## <a id="AppSourceContext"></a>**AppSourceContext** -> Deliver to AppSource

Adding a secret called AppSourceContext to an AL-Go for GitHub repository from the AppSource template, enables automatic delivery to AppSource.

### Managed identity

Managed identities cannot be used for this as this is not an Azure resource

### App Registration (Service to service authentication)

In order to use an app registration for publishing apps to AppSource, you need to register the ClientId (Application Id) of is app registration in Partner Center. After this, there are two ways you can authenticate, either using Federated credential or using a Client Secret.

#### Federated credential

Using a federated credential, you need to register your GitHub repository in the app registration under Certificates & Secrets. This registration will allow AL-Go for GitHub running in this repository to authenticate without the Client Secret stored. You still need to create a secret containing this information. The way this works is that AL-Go for GitHub will request an ID_TOKEN from GitHub as a proof of authenticity and use this when authenticating. This way, only workflows running in the specified branch/environment in GitHub will be able to authenticate.

Example:`{"clientId":"d48b773f-2c26-4394-8bd2-c5b64e0cae32","tenantId":"c645f7e7-0613-4b82-88ca-71f3dbb40045","scopes":"https://api.partner.microsoft.com/.default"}`

#### Client Secret

Under Certificates & Secrets in the app registration, you can create a Client Secret, which you can specify in the AuthContext secret in AL-Go for GitHub. Note that who ever has access to the clientId and clientSecret can publish apps on AppSource on your behalf.

Example: `{"tenantId":"c645f7e7-0613-4b82-88ca-71f3dbb40045","scopes":"https://api.partner.microsoft.com/.default","clientId":"d48b773f-2c26-4394-8bd2-c5b64e0cae32","clientSecret":"OPXxxxxxxxxxxxxxxxxxxxxxxabge"}`

## <a id="StorageContext"></a>**StorageContext** -> Deliver to storage

Adding a secret called StorageContext to an AL-Go for GitHub repository, enables automatic delivery to an Azure storage account.

In AL-Go for GitHub, the Storage Context can be specified in 5 different ways, 5 different authentication mechanism towards an Azure Storage Account.

### Managed Identity/Federated credential

As a storage account is an Azure resource, we can use managed identities. Managed identities are like virtual users in Azure, using federated credentials for authentication. Using a federated credential, you need to register your GitHub repository in the managed identity under Settings -> Federated Credentials. The way this works is that AL-Go for GitHub will request an ID_TOKEN from GitHub as a proof of authenticity and use this when authenticating. This way, only workflows running in the specified branch/environment in GitHub will be able to authenticate.

Example: `{"storageAccountName":"MyStorageName","clientId":"08b6d80c-68cf-48f9-a5ff-b054326e2ec3","tenantId":"c645f7e7-0613-4b82-88ca-71f3dbb40045","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### App Registration/Federated credential

An app registration with federated credential is harder to setup than a managed identity, but just as secure. The mechanism is the same for obtaining an ID_TOKEN and providing this as proof of authenticity towards the app registration.

Example: `{"storageAccountName":"MyStorageName","clientId":"d48b773f-2c26-4394-8bd2-c5b64e0cae32","tenantId":"c645f7e7-0613-4b82-88ca-71f3dbb40045","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### App Registration/Client Secret

An app registration with a client Secret is less secure than using federated credentials. Who ever has access to the clientSecret has access to everything the app registration has access to, until you recycle the client Secret.

Example: `{"storageAccountName":"MyStorageName","clientId":"d48b773f-2c26-4394-8bd2-c5b64e0cae32","clientSecret":"OPXxxxxxxxxxxxxxxxxxxxxxxabge","tenantId":"c645f7e7-0613-4b82-88ca-71f3dbb40045","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### storageAccountName/sastoken

A sas token for a storage account can be setup to function in a limited timeframe, giving access to perform a certain number of tasks on the storage account. Who ever has access to the sastoken can perform these tasks on the storage account until it expires or you recycle the storage account key used to create the sastoken.

Example: `{"storageAccountName":"MyStorageName","sastoken":"sv=2022-11-02&ss=b&srt=sco&sp=rwdlaciytf&se=2024-08-06T20:22:08Z&st=2024-04-06T12:22:08Z&spr=https&sig=IZyIf5xxxxxxxxxxxxxxxxxxxxxtq7tj6b5I%3D","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"}`

### storageAccountName/storageAccountKey

Using storageAccount Name and Key is by far the most unsecure way of authenticating to an Azure Storage Account. If ever compromised, people can do anything with these credentials, until the storageAccount key is cycled.

Example: `{"storageAccountName":"MyStorageName","storageAccountKey":"JHFZErCyfQ8xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxStj7AHXQ==","containerName":"{project}","blobName":"{version}/{project}-{type}.zip"} `

## <a id="GitHubPackagesContext"></a>**GitHubPackagesContext** -> Deliver to GitHub Packages

If you create a secret called GitHubPackagesContext, then AL-Go for GitHub will automagically deliver apps to this NuGet feed after every successful build. AL-Go for GitHub will also use this NuGet feed for dependency resolution when building apps, giving you automatic dependency resolution within all your apps.

Example: `{"token":"ghp_NDdI2ExxxxxxxxxxxxxxxxxAYQh","serverUrl":"https://nuget.pkg.github.com/mygithuborg/index.json"}`
