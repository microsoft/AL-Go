# Partitioning tests by required isolation

Business Central test codeunits can declare, per codeunit, what transactional isolation they need from the test runner that executes them (`RequiredTestIsolation`, runtime 16+). The standard test runner shipped by BC has a single fixed `TestIsolation` value and cannot satisfy multiple requirements at once. AL-Go for GitHub lets you split a single test stage into multiple runs — each driven by a test runner whose `TestIsolation` matches a chosen group of codeunits — so tests behave the same in CI as they do in the BC Test Tool.

## Background: three AL properties

| Property | Applies to | Values | Runtime |
|---|---|---|---|
| `TestIsolation` | Test **runner** codeunit (`Subtype = TestRunner`) | `Disabled` (default), `Codeunit`, `Function` | 1.0 |
| `RequiredTestIsolation` | Test codeunit (`Subtype = Test`) | `None` (default), `Disabled`, `Codeunit`, `Function` | 16.0 (BC 2025 W2+) |
| `TestType` | Test codeunit | `UnitTest` (default), `IntegrationTest`, `Uncategorized`, `AITest` | 16.0 |

The runner's `TestIsolation` decides actual database rollback behavior after tests execute. The test codeunit's `RequiredTestIsolation` is a declaration of what the codeunit expects. If the runner doesn't satisfy it, the test may fail. See Microsoft's [TestIsolation property](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/properties/devenv-testisolation-property) and [RequiredTestIsolation property](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/properties/devenv-requiredtestisolation-property) docs for full semantics.

## When to enable this

Enable `testIsolation` only if some of your test codeunits need a non-default test runner. Projects whose tests all run under the BC default runner do not need this feature.

You supply the runner codeunits — typically by adopting one of the [BCApps Test Runner](https://github.com/microsoft/BCApps/tree/main/src/Tools/Test%20Framework/Test%20Runner) codeunits, or by authoring your own `Subtype = TestRunner` codeunit with the `TestIsolation` property set to the value you need. Your runner codeunit must be installed in the container at test time (typically as part of a test app or a test-runner app).

## Configuration

Add a `testIsolation` block to your `.AL-Go/settings.json` (or any higher-precedence settings location — see [settings.md](settings.md#where-are-the-settings-located)):

```json
{
  "testIsolation": {
    "enabled": true,
    "defaultRunnerCodeunitId": 0,
    "partitions": [
      { "runnerCodeunitId": 130451, "codeunits": "60200..60299" },
      { "runnerCodeunitId": 130452, "codeunits": "60300|60301" }
    ]
  }
}
```

| Key | Meaning |
|---|---|
| `enabled` | Master switch. `false` (default) — AL-Go uses the standard single-pass test behavior. |
| `defaultRunnerCodeunitId` | Runner used for every test codeunit not matched by an entry in `partitions`. `0` means "let BcContainerHelper pick the BC default runner." |
| `partitions[].runnerCodeunitId` | Codeunit ID of the test runner that will execute the codeunits matched by this entry. Must be a `Subtype = TestRunner` codeunit reachable in the container. |
| `partitions[].codeunits` | A BC filter expression matching the test codeunits to run under that runner. Same syntax you would type into the BC Test Tool's `TestCodeunitRangeFilter` — see below. |

### `codeunits` filter syntax

`codeunits` is passed verbatim to BC's test runner page filter, so anything BC accepts as an integer-field filter works:

| Syntax | Meaning |
|---|---|
| `60100` | exact codeunit ID |
| `60100\|60101\|60102` | enumeration (OR) |
| `60100..60199` | inclusive range |
| `60100\|60200..60299` | combined |

You don't need to use `<>` (not equal) in `codeunits` — AL-Go automatically derives the inverse to route every other codeunit to `defaultRunnerCodeunitId`.

## How AL-Go uses this

When `testIsolation.enabled` is `true`, AL-Go installs a custom `RunTestsInBcContainer` scriptblock into Run-AlPipeline. For each test app, the scriptblock:

1. Invokes `Run-TestsInBcContainer` once per entry in `partitions`, with `-testRunnerCodeunitId` set to the partition's runner and `-testCodeunitRange` set to the partition's `codeunits` filter.
2. Issues one trailing call under `defaultRunnerCodeunitId` whose `-testCodeunitRange` is the negation of every explicit partition's filter — so every test codeunit not in any partition runs exactly once under the default runner.

Container lifecycle, app installation, and `disabledTests.json` discovery continue to be handled by Run-AlPipeline. Results are appended into the same JUnit file that downstream reporting (`AnalyzeTests`) already consumes — no other workflow steps need to change.

## Workflow-specific overrides

The normal AL-Go settings cascade applies. To use partitioning only in your nightly workflow, add a `.AL-Go/<workflow-name>.settings.json` containing the `testIsolation` block — the CI workflow runs unchanged.

## Compatibility

- **Requires BC 15+ (test page 130455).** Partitioning works by typing a filter expression into the BC test page's `TestCodeunitRangeFilter` control. That control exists on the standard test page used by BC 15 and later. On BC 14 and earlier (test page 130409) the control is not present, BcContainerHelper silently no-ops the filter, and every partition's call would run **all** test codeunits — producing wrong results. If you need this feature on an older BC version, supply a custom `testPage` setting that points to a page exposing the control, or stay on the single-pass behavior.
- **No source changes are required** to use this feature. The relationship between an in-source `RequiredTestIsolation = Function` declaration and a `partitions` entry that routes that codeunit to a `TestIsolation = Function` runner is your responsibility to keep aligned. Future BC tooling may automate this mapping; until then, settings are the source of truth for CI.
- **`disabledTests.json` continues to work transparently.** Run-AlPipeline aggregates the disabled-test list per app and passes it via the scriptblock parameters; AL-Go forwards it to every partition call, so a disabled test is excluded from every runner.
- **Existing projects are not affected** unless they opt in via `testIsolation.enabled = true`.

## Edge cases

- **Empty `partitions` with `enabled: true`.** The pipeline issues exactly one `Run-TestsInBcContainer` call per test app under `defaultRunnerCodeunitId` (or BC's default if it is `0`) with no codeunit filter. Use this when you want to swap the standard test runner project-wide without partitioning.
- **A codeunit ID listed in two `partitions` entries.** AL-Go does not validate this; both entries fire, so the codeunit runs twice under different runners and appears twice in the JUnit results. Make sure your `codeunits` filters do not overlap.
- **A codeunit ID listed in a `partitions` entry but not present in any test app.** BC's filter ignores unmatched IDs — harmless, no error.
- **Cloud / `useCompilerFolder` runs.** Run-AlPipeline calls the override with `compilerFolder` instead of `containerName`; AL-Go forwards parameters verbatim, so the same partitioning works.
- **BCPT and PageScripting tests** go through different Run-AlPipeline scriptblocks (`-RunBCPTTestsInBcContainer`, `-RunPageScriptingTestsInBcContainer`) and are unaffected by `testIsolation`.

## Performance

Each entry in `partitions` adds one `Run-TestsInBcContainer` call per test app, plus one trailing default-runner call. For N partitions and M test apps, that is `(N + 1) * M` invocations — versus 1 invocation per test app today. Each call has fixed per-invocation overhead (BC test page setup, control population). Enable `testIsolation` only when isolation requirements actually demand it.

## Related

- [TestIsolation property](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/properties/devenv-testisolation-property)
- [RequiredTestIsolation property](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/properties/devenv-requiredtestisolation-property)
- [TestType property](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/properties/devenv-testtype-property)
- [Test Runner codeunits](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-testrunner-codeunits)
- [BCApps Test Runner](https://github.com/microsoft/BCApps/tree/main/src/Tools/Test%20Framework/Test%20Runner)

______________________________________________________________________

[back](../README.md)
