# E2E Setup Repositories

Sets up test repositories for E2E testing by calling the SetupRepositories.ps1 script.

## Inputs

- `githubOwner`: GitHub owner for test repositories
- `bcContainerHelperVersion`: BcContainerHelper version
- `token`: GitHub token with permissions to create repositories

## Outputs

- `actionsRepo`: Actions repository name
- `perTenantExtensionRepo`: Per-tenant extension repository name
- `appSourceAppRepo`: AppSource app repository name
