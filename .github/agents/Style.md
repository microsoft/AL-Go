# Style Rules

## Important (Should Flag)

1. **Missing tests**: New or modified functions should have corresponding Pester tests in `Tests/`
2. **Cross-platform issues**: Hardcoded path separators, PS5-only or PS7-only constructs
3. **Encoding omissions**: File read/write without explicit `-Encoding UTF8`
4. **YAML permissions**: Workflows without minimal permission declarations

## Informational (May Flag)

1. Opportunities to use existing helper functions from `AL-Go-Helper.ps1` or shared modules
2. Inconsistent naming (should be PascalCase functions, camelCase variables)
