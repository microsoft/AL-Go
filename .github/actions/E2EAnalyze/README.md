# E2E Analyze

Analyzes and generates test matrices for E2E testing including public/private test runs, releases, and scenarios.

## Inputs

- `maxParallel`: Maximum parallel jobs
- `testUpgradesFromVersion`: Test upgrades from version (default: 'v5.0')
- `token`: GitHub token with permissions to read releases

## Outputs

- `publictestruns`: Public test runs matrix
- `privatetestruns`: Private test runs matrix
- `releases`: Releases matrix
- `scenarios`: Scenarios matrix
