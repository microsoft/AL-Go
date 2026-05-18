# E2E Run Test

Runs E2E tests by executing Test-AL-Go.ps1 or Test-AL-Go-Upgrade.ps1 scripts.

## Inputs

- `testType`: Test type (test or upgrade, default: test)
- `private`: Private repository (default: false)
- `githubOwner`: GitHub owner
- `repoName`: Repository name
- `e2eAppId`: E2E App ID
- `e2eAppKey`: E2E App Key
- `algoAuthApp`: ALGO Auth App
- `template`: Template
- `adminCenterApiCredentials`: Admin center API credentials
- `multiProject`: Multi-project (default: false)
- `appSource`: AppSource app (default: false)
- `linux`: Linux (default: false)
- `useCompilerFolder`: Use compiler folder (default: false)
- `release`: Release (for upgrade tests)
- `contentPath`: Content path (for upgrade tests)
