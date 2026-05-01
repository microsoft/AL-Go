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
- **Method-level detail lost in multi-job merge:** When coverage is collected across multiple build jobs, the merge uses union semantics at the line level. Method-level detail from individual jobs is not preserved in the merged output.
- **No branch coverage:** Business Central does not expose branch-level coverage data. Only line-level coverage (hit/not hit) is reported.
- **No threshold enforcement:** Coverage data is informational only. There is no built-in mechanism to fail the build if coverage drops below a threshold.
- **Performance impact:** Coverage collection adds overhead to test execution. Large codebases with many test apps may see increased build times. Use `trackingType: PerRun` (the default) for best performance.
- **File size:** Coverage data files can be significant for large codebases. The GitHub Step Summary is automatically truncated if it exceeds size limits; download the CodeCoverage artifact for full details.

## Integration with Third-Party Tools

The `cobertura.xml` output follows the standard [Cobertura XML format](https://cobertura.github.io/cobertura/), which is widely supported by coverage visualization and CI/CD tools. You can download the `CodeCoverage` artifact from your workflow run and upload it to services such as:

- **SonarQube / SonarCloud** — Import via the `sonar.coverageReportPaths` property
- **Codecov.io** — Upload using the [Codecov GitHub Action](https://github.com/codecov/codecov-action) with the artifact path
- **Azure DevOps** — Use the [Publish Code Coverage Results](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/test/publish-code-coverage-results) task

Example workflow step to upload coverage to a third-party tool after the build:

```yaml
- name: Download coverage artifact
  uses: actions/download-artifact@v4
  with:
    name: MergedCodeCoverage
    path: .coverage
- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: .coverage/cobertura.xml
```

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
