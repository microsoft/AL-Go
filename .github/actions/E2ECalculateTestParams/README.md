# E2E Calculate Test Parameters

Calculates test parameters including template repository, admin center credentials, and repository name based on matrix configuration.

## Inputs

- `githubOwner`: GitHub owner for test repositories
- `matrixType`: Matrix type (PTE or appSourceApp)
- `matrixStyle`: Matrix style (singleProject or multiProject)
- `matrixOs`: Matrix OS (windows or linux)
- `adminCenterApiCredentialsSecret`: Admin center API credentials secret
- `appSourceAppRepo`: AppSource app repository template
- `perTenantExtensionRepo`: Per-tenant extension repository template
- `contentPath`: Content path (for upgrade tests)

## Outputs

- `adminCenterApiCredentials`: Calculated admin center API credentials
- `template`: Calculated template repository
- `repoName`: Generated repository name
- `contentPath`: Content path (for upgrade tests)
