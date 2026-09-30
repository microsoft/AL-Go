# E2E Check Secrets

Validates that all required secrets and variables are configured for E2E testing.

## Inputs

- `githubOwner`: GitHub owner (defaults to current repository owner)
- `e2eAppId`: E2E_APP_ID variable value
- `e2ePrivateKey`: E2E_PRIVATE_KEY secret value
- `algoAuthApp`: ALGOAUTHAPP secret value
- `adminCenterApiCredentials`: adminCenterApiCredentials secret value
- `e2eGHPackagesPAT`: E2E_GHPackagesPAT secret value
- `e2eAzureCredentials`: E2EAZURECREDENTIALS secret value

## Outputs

- `maxParallel`: Maximum number of parallel jobs
- `githubOwner`: GitHub owner for test repositories
