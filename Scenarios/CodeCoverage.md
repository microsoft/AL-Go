# Collect Code Coverage

> **Preview:** This feature is work-in-progress and is not guaranteed to work in all scenarios and setups yet. If you encounter issues, disable the setting and report the problem.

AL-Go for GitHub supports collecting code coverage data during test runs. When enabled, the pipeline uses the AL Test Runner to execute tests and collect line-level coverage information, which is output as a Cobertura XML file in the build artifacts.

## Enabling Code Coverage

Add the following to your `.AL-Go/settings.json` or `.github/AL-Go-Settings.json`:

```json
{
    "enableCodeCoverage": true
}
```

Read more about settings at [Settings](settings.md#enableCodeCoverage).

## Advanced Configuration

Use the `codeCoverageSetup` object to customize coverage behavior:

```json
{
    "enableCodeCoverage": true,
    "codeCoverageSetup": {
        "excludeFilesPattern": ["*.PermissionSet.al", "*.PermissionSetExtension.al"],
        "trackingType": "PerRun",
        "produceCodeCoverageMap": "PerCodeunit"
    }
}
```

| Property | Description | Default |
|---|---|---|
| `excludeFilesPattern` | Array of glob patterns for files to exclude from the coverage denominator. Patterns are matched against both the file name and relative path. Example: `["*.PermissionSet.al"]` excludes all permission set files. | `[]` |
| `trackingType` | Coverage tracking granularity: `PerRun`, `PerCodeunit`, or `PerTest`. | `PerRun` |
| `produceCodeCoverageMap` | Code coverage map granularity: `Disabled`, `PerCodeunit`, or `PerTest`. | `PerCodeunit` |

Read more about settings at [Settings](settings.md#codeCoverageSetup).

## Output

The coverage output is available in the build artifacts under the `CodeCoverage` folder:

- **`cobertura.xml`** — Coverage data in Cobertura XML format, suitable for integration with coverage visualization tools.
- **`.dat` files** — Raw coverage data from the AL Test Runner.

## Limitations

- **Custom `RunTestsInBcContainer` overrides:** If your repository has a custom `RunTestsInBcContainer.ps1` override in the `.AL-Go` folder, it will take precedence over the built-in code coverage override. A warning will be emitted in the build log. To collect code coverage with a custom override, your script must use `Run-AlTests` (imported automatically by AL-Go) with the appropriate code coverage parameters.
- **Work-in-progress:** The AL Test Runner is a new component and may not support all test configurations that the standard BcContainerHelper test runner supports. If you experience test failures or missing test results after enabling code coverage, disable the setting and report the issue.

## Using Code Coverage with a Custom Override

If you need a custom `RunTestsInBcContainer.ps1` override and also want code coverage, your script can call `Run-AlTests` directly. The module is imported automatically by AL-Go at pipeline startup. Key parameters for code coverage:

```powershell
Run-AlTests @{
    ServiceUrl               = $serviceUrl
    Credential               = $credential
    CodeCoverageTrackingType  = 'PerRun'
    ProduceCodeCoverageMap    = 'PerCodeunit'
    CodeCoverageOutputPath    = $codeCoverageOutputPath
    # ... other test parameters
}
```

See the [AL-Go Settings](settings.md) documentation for the full list of available pipeline override scripts.
