# Security Rules

## Critical (Must Flag)

1. **Missing error handling**: Scripts must start with `$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0`
2. **Secret leakage**: Any path where a secret value could appear in logs, error messages, or output without being masked via `::add-mask::`
3. **Path traversal**: File operations that don't validate paths stay within the workspace
4. **Missing `-recurse` on ConvertTo-HashTable**: After `ConvertFrom-Json`, always chain `| ConvertTo-HashTable -recurse` for case-insensitive access
5. **Deprecated settings**: Flag usage of settings listed in `DEPRECATIONS.md`
