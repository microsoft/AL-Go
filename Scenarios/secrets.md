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

### Secret values masked in logs

All secrets exposed to a repository will be masked (replaced with ***) in the workflow logs of that repository. This is good, as this ensures that secrets are not exposed 


### Only expose secrets necessary secrets to AL-Go repositories

You should only make 

### Don't have secrets that are not secret


### Compressed json

### Avoid secrets alltogether

By using managed identities and federated credentials, you can avoid having secrets 

## Microsoft Entra App Registration

### Federated credentials vs. clientSecret

## Managed identities (For accessing Azure resources)

### Federated credentials




## Connect to Azure (Azure_Credentials)

### Read secrets from KeyVault

Two security models for KeyVaults

### Sign an app

Keyvault must be premium SKU + how to change SKU using AZ CLI

### Create Azure VMs???

## <a id="AuthContext"></a>Deploy to an environment (AuthContext)

## <a id="AppSourceContext"></a>Deliver to AppSource (AppSourceContext)

## <a id="StorageContext"></a>Deliver to storage (StorageContext)

Different auth models

## <a id="NuGetContext"></a>Deliver to NuGet (NuGetContext)

## <a id="GitHubPackagesContext"></a>Deliver to GitHub Packages (GitHubPackagesContext)
